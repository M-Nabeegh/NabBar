import Foundation
import Testing
@testable import Quotas

/// NabBar's Info.plist names its folder and the providers it shows; without
/// those keys it still keeps to `~/.nabbar` and shows every provider.
@Suite
struct AppProfileTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - Home folder

    @Test
    func `without a folder key the files stay in dot nabbar`() {
        #expect(AppProfile.homeDirectory(info: [:]) == home.appendingPathComponent(".nabbar", isDirectory: true))
        #expect(AppProfile.homeDirectory(info: nil) == home.appendingPathComponent(".nabbar", isDirectory: true))
    }

    @Test
    func `a build keeps its files in the folder it names`() {
        let info: [String: Any] = [AppProfile.homeDirectoryKey: ".nabbar-dev"]

        #expect(AppProfile.homeDirectory(info: info) == home.appendingPathComponent(".nabbar-dev", isDirectory: true))
    }

    @Test
    func `an empty folder name falls back to dot nabbar`() {
        let info: [String: Any] = [AppProfile.homeDirectoryKey: ""]

        #expect(AppProfile.homeDirectory(info: info) == home.appendingPathComponent(".nabbar", isDirectory: true))
    }

    // MARK: - Display name

    @Test
    func `without a display name the app is called NabBar`() {
        #expect(AppProfile.displayName(info: [:]) == "NabBar")
        #expect(AppProfile.displayName(info: ["CFBundleDisplayName": ""]) == "NabBar")
    }

    @Test
    func `the bundle display name wins`() {
        #expect(AppProfile.displayName(info: ["CFBundleDisplayName": "NabBar Dev"]) == "NabBar Dev")
    }

    // MARK: - Provider lineup

    @Test
    func `without a lineup key every provider shows`() {
        #expect(AppProfile.providerLineup(info: [:]) == nil)
        #expect(AppProfile.providerLineup(info: [AppProfile.providerLineupKey: [String]()]) == nil)
    }

    @Test
    func `the providers sent to Notify are read in order`() {
        #expect(AppProfile.notifyProviders(info: [AppProfile.notifyProvidersKey: ["claude", "codex"]]) == ["claude", "codex"])
        #expect(AppProfile.notifyProviders(info: [:]) == nil)
    }

    @Test
    func `the lineup is read in order`() {
        let info: [String: Any] = [AppProfile.providerLineupKey: ["codex", "claude", "commandcode"]]

        #expect(AppProfile.providerLineup(info: info) == ["codex", "claude", "commandcode"])
    }

    @Test
    func `arranging by a lineup orders codex claude command code and drops the rest`() {
        let registered = ["claude", "codex", "gemini", "antigravity", "zai", "copilot", "cursor", "commandcode"]

        let shown = AppProfile.arrange(registered, id: { $0 }, lineup: ["codex", "claude", "commandcode"])

        #expect(shown == ["codex", "claude", "commandcode"])
    }

    @Test
    func `a lineup id that is not registered is skipped`() {
        let shown = AppProfile.arrange(["claude", "codex"], id: { $0 }, lineup: ["codex", "claude", "commandcode"])

        #expect(shown == ["codex", "claude"])
    }

    @Test
    func `without a lineup every provider stays in registration order`() {
        let registered = ["claude", "codex", "gemini", "commandcode"]

        #expect(AppProfile.arrange(registered, id: { $0 }, lineup: nil) == registered)
    }
}
