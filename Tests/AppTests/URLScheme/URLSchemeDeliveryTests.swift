import Testing
import AppKit
@testable import NabBar

/// The app delegate is the one object guaranteed to exist when a
/// `nabbar://` URL arrives, including when the URL is what launched the
/// app. These tests pin down that no action is lost across that gap.
@Suite @MainActor
struct URLSchemeDeliveryTests {

    @Test
    func `actions are delivered to the handler in order`() {
        let delegate = AppDelegate()
        var received: [URLSchemeAction] = []
        delegate.onAction = { received.append($0) }

        delegate.application(NSApp, open: [
            URL(string: "nabbar://refresh")!,
            URL(string: "nabbar://open")!,
        ])

        #expect(received == [.refresh, .open])
    }

    @Test
    func `actions that arrive before the handler is installed wait for it`() {
        let delegate = AppDelegate()
        delegate.application(NSApp, open: [URL(string: "nabbar://open")!])

        var received: [URLSchemeAction] = []
        delegate.onAction = { received.append($0) }

        #expect(received == [.open])
    }

    @Test
    func `held actions are delivered once`() {
        let delegate = AppDelegate()
        delegate.application(NSApp, open: [URL(string: "nabbar://open")!])
        var received: [URLSchemeAction] = []
        delegate.onAction = { received.append($0) }

        delegate.application(NSApp, open: [URL(string: "nabbar://settings")!])

        #expect(received == [.open, .settings])
    }

    @Test
    func `unknown URLs deliver nothing`() {
        let delegate = AppDelegate()
        var received: [URLSchemeAction] = []
        delegate.onAction = { received.append($0) }

        delegate.application(NSApp, open: [URL(string: "nabbar://foo")!])

        #expect(received.isEmpty)
    }
}
