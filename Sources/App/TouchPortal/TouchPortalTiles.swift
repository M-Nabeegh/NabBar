import AppKit
import Domain
import SwiftUI

/// Finished button faces for Touch Portal, one PNG per provider in
/// `~/.nabbar/tiles/<id>.png`: logo and name, the 5h window large in its
/// status colour, the weekly window as a bar. The plugin can only draw shapes,
/// so the app, which has the logos and the fonts, draws the whole face.
@MainActor
enum TouchPortalTiles {
    /// Points; the PNG is twice this.
    static let size: CGFloat = 256

    static var directory: URL {
        AppProfile.homeDirectory.appendingPathComponent("tiles", isDirectory: true)
    }

    /// Writes a tile for each provider whose face changed.
    static func write(_ providers: [StatusExportDriver.ExportPayload.ProviderSummary]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for provider in providers {
            guard let png = png(for: provider) else { continue }
            let url = directory.appendingPathComponent("\(provider.id).png")
            if (try? Data(contentsOf: url)) == png { continue }
            try? png.write(to: url, options: .atomic)
        }
    }

    static func png(for provider: StatusExportDriver.ExportPayload.ProviderSummary) -> Data? {
        let tile = TouchPortalTileView(
            name: provider.name,
            logo: NSImage(named: ProviderVisualIdentityLookup.iconAssetName(for: provider.id)),
            session: provider.percentRemaining,
            sessionReset: shortReset(provider.resetText),
            weekly: provider.weeklyPercentRemaining
        )
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// "Resets 2:20am (Asia/Karachi)" → "2:20am", "Resets in 34m" → "in 34m".
    static func shortReset(_ text: String?) -> String? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("resets ") { text = String(text.dropFirst("resets ".count)) }
        if let zone = text.range(of: " (") { text = String(text[..<zone.lowerBound]) }
        return text
    }
}

/// One tile. Colours follow NabBar's status thresholds (50/20/0% left).
struct TouchPortalTileView: View {
    let name: String
    let logo: NSImage?
    let session: Double?
    let sessionReset: String?
    let weekly: Double?

    private let ink = Color(red: 0.90, green: 0.91, blue: 0.92)
    private let muted = Color(red: 0.58, green: 0.61, blue: 0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text(name)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.colour(for: session))
                Text("5h")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(muted)
            }
            Text(sessionReset.map { "resets \($0)" } ?? " ")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(muted)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Text("7d")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(muted)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Self.colour(for: weekly))
                        .frame(width: 112 * CGFloat(max(0, min(100, weekly ?? 0)) / 100))
                }
                .frame(width: 112, height: 10)
                Text(weekly.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.colour(for: weekly))
            }
        }
        .padding(22)
        .frame(width: TouchPortalTiles.size, height: TouchPortalTiles.size, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.165, green: 0.180, blue: 0.204), Color(red: 0.102, green: 0.114, blue: 0.129)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 2)
        )
    }

    static func colour(for percentLeft: Double?) -> Color {
        guard let percentLeft else { return Color(red: 0.42, green: 0.44, blue: 0.47) }
        switch QuotaStatus.from(percentRemaining: percentLeft) {
        case .healthy: return Color(red: 0.310, green: 0.890, blue: 0.651)   // #4FE3A6
        case .warning: return Color(red: 0.969, green: 0.725, blue: 0.333)   // #F7B955
        case .critical: return Color(red: 0.949, green: 0.408, blue: 0.494)  // #F2687E
        case .depleted: return Color(red: 0.851, green: 0.239, blue: 0.333)  // #D93D55
        }
    }
}
