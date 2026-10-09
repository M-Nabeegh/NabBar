import AppKit
import Testing
import Domain
@testable import NabBar

/// The dot on a logo in the menu bar: blue while Claude Code or Codex works,
/// green once it finished, none when idle.
@Suite @MainActor
struct MenuBarActivityBadgeTests {
    private let logo = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
        NSColor.gray.setFill(); bounds.fill(); return true
    }

    /// The colour at the dot's centre, in device RGB.
    private func corner(_ image: NSImage) throws -> NSColor {
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let x = rep.pixelsWide * 13 / 16, y = rep.pixelsHigh * 3 / 16   // top right, bitmap rows run downward
        return try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    @Test
    func `idle leaves the logo as it is`() {
        #expect(StatusItemLabelDriver.badged(logo, activity: .idle, dark: true) === logo)
        #expect(StatusItemLabelDriver.badged(logo, activity: nil, dark: true) === logo)
    }

    @Test
    func `working puts a blue dot on the corner`() throws {
        let colour = try corner(StatusItemLabelDriver.badged(logo, activity: .working, dark: true))

        #expect(colour.blueComponent > 0.9 && colour.redComponent < 0.5)
    }

    @Test
    func `finished puts a green dot on the corner`() throws {
        let colour = try corner(StatusItemLabelDriver.badged(logo, activity: .finished(at: Date()), dark: true))

        #expect(colour.greenComponent > 0.8 && colour.redComponent < 0.5)
    }
}
