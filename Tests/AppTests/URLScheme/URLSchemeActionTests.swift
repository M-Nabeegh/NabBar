import Testing
import Foundation
@testable import NabBar

@Suite
struct URLSchemeActionTests {

    @Test(arguments: [
        ("nabbar://open", URLSchemeAction.open),
        ("nabbar://refresh", .refresh),
        ("nabbar://settings", .settings),
    ])
    func `the documented URLs are actions`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test(arguments: [
        ("nabbar:///open", URLSchemeAction.open),
        ("nabbar:///refresh", .refresh),
        ("nabbar:///settings", .settings),
    ])
    func `the three-slash spelling is the same action`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test
    func `scheme and action are matched case-insensitively`() {
        let url = URL(string: "NABBAR://Open")!
        #expect(URLSchemeAction(url: url) == .open)
    }

    @Test(arguments: [
        "nabbar://foo",
        "nabbar://",
        "nabbar:///",
        "nabbar://refresh/other?unexpected=1",
        "nabbar://open?x=1",
        "nabbar://open#top",
        "nabbar://open/",
        "nabbar://open/extra",
        "nabbar:///open/extra",
        "nabbar:///settings/",
        "nabbar:///settings?x=1",
        "nabbar://guest@refresh",
        "nabbar://refresh:443",
        "nabbar://user:pass@settings",
        "https://open",
    ])
    func `anything that is not exactly a documented URL is nil`(string: String) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == nil)
    }
}
