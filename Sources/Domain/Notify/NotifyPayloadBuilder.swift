import Quotas
import DataSources
import Providers
import Foundation

/// Turns quota readings into the tile and gauge ClaudeBar publishes to Notify!.
///
/// This is the whole decision layer of the feature and it is deliberately pure:
/// no clock of its own, no network, no settings lookups. What to show, in what
/// order, in what words, and in what color is decided here so it can be tested
/// as plain state assertions.
///
/// The rules:
/// 1. The worst quota leads. Readings sort by status severity, then by how
///    little is left, so the number that needs attention is the headline and
///    the tile takes its color and progress bar from it.
/// 2. The tile carries up to six windows as a metrics row, because six is the
///    gateway's ceiling and more than six is unreadable on a Lock Screen.
/// 3. Labels drop the provider name when every reading comes from the same
///    provider, so a single provider tile reads "5h  7d" rather than
///    "Claude 5h  Claude 7d".
/// 4. Percentages are remaining, not used. Every ClaudeBar surface reads that
///    way, and a full bar meaning a full quota is the only intuitive mapping
///    for a gauge.
public struct NotifyPayloadBuilder: Sendable {
    /// The tile and widget title. Both name the sending app rather than the
    /// current quota: the gateway treats a title as an identity, and a widget
    /// that renamed itself whenever the user switched provider would be
    /// unrecognizable in the phone's widget picker.
    public static let defaultTitle = "NabBar"

    private let title: String
    /// One chip per provider holding its 5h and 7d windows, in the order the
    /// readings come in, instead of one chip per window, worst first. A medium
    /// Home Screen widget draws two chips, so two providers fit with both windows.
    private let pairsWindowsByProvider: Bool

    public init(title: String = NotifyPayloadBuilder.defaultTitle, pairsWindowsByProvider: Bool = false) {
        self.title = title
        self.pairsWindowsByProvider = pairsWindowsByProvider
    }

    public func payload(
        readings: [NotifyQuotaReading],
        gaugeSelection: NotifyGaugeSelection = .automatic,
        includesTile: Bool = true,
        includesGauge: Bool = true,
        includesScreenTile: Bool = true,
        statusPolicy: StatusPolicy = .absolute
    ) -> NotifyPayload {
        let ordered = Self.ordered(readings, under: statusPolicy)
        guard let headline = ordered.first else { return .empty }

        // The Live Activity and the Home Screen tile are built once and shared.
        // The gateway takes the same body on both routes, so building them twice
        // could only produce two things that were supposed to be identical and
        // one day were not.
        let tile = (includesTile || includesScreenTile)
            ? self.tile(readings: readings, ordered: ordered, headline: headline, policy: statusPolicy)
            : nil

        return NotifyPayload(
            tile: includesTile ? tile : nil,
            gauge: includesGauge ? gauge(ordered: ordered, headline: headline, selection: gaugeSelection, policy: statusPolicy) : nil,
            screenTile: includesScreenTile ? tile : nil
        )
    }

    // MARK: - Ordering

    /// Worst first, and fully deterministic: two payloads built from the same
    /// readings must compare equal, or the driver would republish forever.
    static func ordered(_ readings: [NotifyQuotaReading], under policy: StatusPolicy = .absolute) -> [NotifyQuotaReading] {
        readings.sorted { left, right in
            let leftStatus = left.quota.status(under: policy)
            let rightStatus = right.quota.status(under: policy)
            if leftStatus != rightStatus { return leftStatus > rightStatus }
            if left.quota.percentRemaining != right.quota.percentRemaining {
                return left.quota.percentRemaining < right.quota.percentRemaining
            }
            if left.providerName != right.providerName { return left.providerName < right.providerName }
            if left.quota.quotaType.quotaKey != right.quota.quotaType.quotaKey {
                return left.quota.quotaType.quotaKey < right.quota.quotaType.quotaKey
            }
            // The last tie break, and the one that makes the comparator total.
            // Display names are not unique: an aggregating provider can report
            // two accounts under one name, and Swift's sort is not stable, so
            // without this two readings that tie on everything else could come
            // back in either order. The payload would then differ between builds
            // of the same state and the driver would republish for nothing.
            return left.providerId < right.providerId
        }
    }

    // MARK: - Tile

    private func tile(
        readings: [NotifyQuotaReading],
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        policy: StatusPolicy
    ) -> NotifyTile? {
        let omitsProviderName = Set(ordered.map(\.providerId)).count == 1
        let metrics = pairsWindowsByProvider
            ? Self.pairedMetrics(readings, policy: policy)
            : ordered
            .prefix(NotifyLimits.metricCount)
            .compactMap { reading in
                NotifyMetric(
                    label: Self.label(for: reading, omittingProviderName: omitsProviderName),
                    value: Self.headlineValue(for: reading.quota),
                    unit: Self.unit(for: reading.quota),
                    tintHex: reading.quota.status(under: policy).notifyTintHex
                )
            }

        return NotifyTile(
            title: title,
            body: Self.summary(for: headline),
            symbolName: NotifySymbol.quota,
            tintHex: headline.quota.status(under: policy).notifyTintHex,
            progress: Self.progress(for: ordered),
            trailing: headline.quota.compactResetTime,
            metrics: metrics
        )
    }

    /// "Claude 5h · 7d" / "44 · 80" %, tinted by the worse of the two windows.
    /// Providers keep the order they arrive in; within one, 5h comes before 7d.
    /// The name always stays: a chip is a provider, even while it is the only
    /// one that has loaded.
    static func pairedMetrics(_ readings: [NotifyQuotaReading], policy: StatusPolicy) -> [NotifyMetric] {
        var providerIds: [String] = []
        for reading in readings where !providerIds.contains(reading.providerId) {
            providerIds.append(reading.providerId)
        }
        return providerIds.prefix(NotifyLimits.metricCount).compactMap { providerId in
            let mine = readings.filter { $0.providerId == providerId && !$0.quota.isDollarBased }
            let windows = [QuotaType.session, .weekly].compactMap { type in mine.first { $0.quota.quotaType == type } }
            guard let first = windows.first else { return nil }
            let worst = windows.map { $0.quota.status(under: policy) }.max() ?? .healthy
            let window = windows.map { Self.windowLabel(for: $0.quota) }.joined(separator: " · ")
            return NotifyMetric(
                label: "\(first.providerName) \(window)",
                value: windows.map { Self.headlineValue(for: $0.quota) }.joined(separator: " · "),
                unit: "%",
                tintHex: worst.notifyTintHex
            )
        }
    }

    // MARK: - Gauge

    private func gauge(
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        selection: NotifyGaugeSelection,
        policy: StatusPolicy
    ) -> NotifyGauge? {
        let shown = Self.selected(from: ordered, selection: selection) ?? headline

        return NotifyGauge(
            title: title,
            value: Self.headlineValue(for: shown.quota),
            unit: Self.unit(for: shown.quota),
            detail: Self.gaugeDetail(for: shown),
            symbolName: NotifySymbol.quota,
            tintHex: shown.quota.status(under: policy).notifyTintHex,
            progress: shown.quota.isDollarBased ? nil : shown.quota.percentRemaining
        )
    }

    /// The reading the user asked the gauge to show, or nil when the selection
    /// is automatic or names a window that is no longer reporting.
    static func selected(
        from readings: [NotifyQuotaReading],
        selection: NotifyGaugeSelection
    ) -> NotifyQuotaReading? {
        guard !selection.isAutomatic else { return nil }
        return readings.first {
            $0.providerId == selection.providerId
                && $0.quota.quotaType.quotaKey == selection.quotaKey
        }
    }

    // MARK: - Words and numbers

    /// "Claude 5h", or just "5h" when the tile only covers one provider.
    static func label(for reading: NotifyQuotaReading, omittingProviderName: Bool) -> String {
        let window = Self.windowLabel(for: reading.quota)
        guard !omittingProviderName else { return window }
        return "\(reading.providerName) \(window)"
    }

    /// The quota's own short title when its probe set one, otherwise the
    /// window's short label ("5h", "7d").
    static func windowLabel(for quota: UsageQuota) -> String {
        quota.compactTitle ?? quota.quotaType.shortLabel
    }

    /// A percentage as a bare integer, or the formatted balance for a quota
    /// measured in money rather than percent.
    static func headlineValue(for quota: UsageQuota) -> String {
        if let balance = quota.formattedDollarRemaining { return balance }
        return "\(Int(quota.percentRemaining.rounded()))"
    }

    static func unit(for quota: UsageQuota) -> String? {
        quota.isDollarBased ? nil : "%"
    }

    /// "Claude 5h, 42% left, resets in 2:14". The tile's body line, which the
    /// gateway shows only when there are no metrics to put in its place, so it
    /// has to carry the number itself.
    static func summary(for reading: NotifyQuotaReading) -> String {
        var parts = ["\(reading.providerName) \(Self.windowLabel(for: reading.quota))"]

        if let balance = reading.quota.formattedDollarRemaining {
            parts.append("\(balance) left")
        } else {
            parts.append("\(Int(reading.quota.percentRemaining.rounded()))% left")
        }

        if let resets = reading.quota.compactResetTime {
            parts.append(resets == "soon" ? "resets soon" : "resets in \(resets)")
        }

        return parts.joined(separator: ", ")
    }

    /// "Claude 5h, resets in 2:14". The widget's quieter line, which sits next
    /// to a headline value that already shows the percentage, so repeating it
    /// here would waste the one short line the widget has.
    static func gaugeDetail(for reading: NotifyQuotaReading) -> String {
        var parts = ["\(reading.providerName) \(Self.windowLabel(for: reading.quota))"]

        if let resets = reading.quota.compactResetTime {
            parts.append(resets == "soon" ? "resets soon" : "resets in \(resets)")
        }

        return parts.joined(separator: ", ")
    }

    /// The bar on the tile. Money-based quotas have no percentage to draw, so
    /// the bar falls through to the worst quota that does have one rather than
    /// disappearing whenever a credit balance happens to be the headline.
    static func progress(for ordered: [NotifyQuotaReading]) -> Double? {
        ordered.first { !$0.quota.isDollarBased }?.quota.percentRemaining
    }
}
