import Foundation
import Testing
import Domain
@testable import NabBar

/// One provider's line in `~/.nabbar/status.json`, which Touch Portal reads:
/// its first window as before, and its weekly window beside it.
@Suite
struct StatusExportSummaryTests {
    private let reset = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `a provider's weekly window is exported beside its first one`() {
        let quotas = [
            UsageQuota(percentRemaining: 44, quotaType: .session, providerId: "claude", resetText: "Resets in 34m"),
            UsageQuota(percentRemaining: 80, quotaType: .weekly, providerId: "claude", resetsAt: reset, resetText: "Resets Oct 5"),
        ]

        let summary = StatusExportDriver.summary(id: "claude", name: "Claude", status: "warning", quotas: quotas)

        #expect(summary.percentRemaining == 44)
        #expect(summary.resetText == "Resets in 34m")
        #expect(summary.weeklyPercentRemaining == 80)
        #expect(summary.weeklyResetText == "Resets Oct 5")
        #expect(summary.weeklyResetsAt == ISO8601DateFormatter().string(from: reset))
    }

    @Test
    func `a provider without a weekly window leaves the weekly fields out`() throws {
        let quotas = [UsageQuota(percentRemaining: 63, quotaType: .session, providerId: "codex")]

        let summary = StatusExportDriver.summary(id: "codex", name: "Codex", status: "healthy", quotas: quotas)
        let json = try #require(String(data: JSONEncoder().encode(summary), encoding: .utf8))

        #expect(summary.weeklyPercentRemaining == nil)
        #expect(!json.contains("weekly"))
    }
}
