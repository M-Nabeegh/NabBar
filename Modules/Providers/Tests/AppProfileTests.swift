import Foundation
import Testing
@testable import Quotas

/// A side-by-side build (NabBar) names its own folder and the
/// providers it shows in its Info.plist; a plain build names neither.
@Suite
struct AppProfileTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - Home folder

    @Test
    func `a plain build keeps its files in dot claudebar`() {
        #expect(AppProfile.homeDirectory(info: [:]) == home.appendingPathComponent(".claudebar", isDirectory: true))
        #expect(AppProfile.homeDirectory(info: nil) == home.appendingPathComponent(".claudebar", isDirectory: true))
    }

    @Test
    func `a local build keeps its files in the folder it names`() {
        let info: [String: Any] = [AppProfile.homeDirectoryKey: ".nabbar"]

        #expect(AppProfile.homeDirectory(info: info) == home.appendingPathComponent(".nabbar", isDirectory: true))
    }

    @Test
    func `an empty folder name falls back to dot claudebar`() {
        let info: [String: Any] = [AppProfile.homeDirectoryKey: ""]

        #expect(AppProfile.homeDirectory(info: info) == home.appendingPathComponent(".claudebar", isDirectory: true))
    }

    // MARK: - Display name

    @Test
    func `a plain build is called ClaudeBar`() {
        #expect(AppProfile.displayName(info: [:]) == "ClaudeBar")
        #expect(AppProfile.displayName(info: ["CFBundleDisplayName": ""]) == "ClaudeBar")
    }

    @Test
    func `a renamed build shows its own display name`() {
        #expect(AppProfile.displayName(info: ["CFBundleDisplayName": "NabBar"]) == "NabBar")
    }

    // MARK: - Provider lineup

    @Test
    func `a plain build has no lineup`() {
        #expect(AppProfile.providerLineup(info: [:]) == nil)
        #expect(AppProfile.providerLineup(info: [AppProfile.providerLineupKey: [String]()]) == nil)
    }

    @Test
    func `a local build reads its lineup in order`() {
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
