import AppKit
import Foundation
import Testing
@testable import NabBar

/// The button faces NabBar draws for Touch Portal: logo, name, the 5h window
/// large, the weekly window as a bar.
@Suite @MainActor
struct TouchPortalTilesTests {
    @Test(arguments: [
        ("Resets in 34m", "in 34m"),
        ("Resets 2:20am (Asia/Karachi)", "2:20am"),
        ("Resets Oct 5 at 9pm (Asia/Karachi)", "Oct 5 at 9pm"),
        ("in 2h", "in 2h"),
    ])
    func `reset text loses its prefix and time zone`(text: String, expected: String) {
        #expect(TouchPortalTiles.shortReset(text) == expected)
    }

    @Test
    func `no reset text gives none`() {
        #expect(TouchPortalTiles.shortReset(nil) == nil)
        #expect(TouchPortalTiles.shortReset("  ") == nil)
    }

    @Test
    func `a provider renders to a square PNG`() throws {
        let summary = StatusExportDriver.ExportPayload.ProviderSummary(
            id: "claude", name: "Claude", status: "healthy",
            percentRemaining: 97, resetText: "Resets 2:20am (Asia/Karachi)",
            weeklyPercentRemaining: 82
        )

        let png = try #require(TouchPortalTiles.png(for: summary))
        let image = try #require(NSBitmapImageRep(data: png))

        #expect(image.pixelsWide == 512)
        #expect(image.pixelsHigh == 512)
    }
}
