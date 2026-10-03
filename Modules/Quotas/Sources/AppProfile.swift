import Foundation

/// Which build of the app this is, read from its Info.plist.
///
/// A plain build has no profile keys and behaves as always: it keeps its files in
/// `~/.claudebar` and shows every provider. A side-by-side build (NabBar)
/// names its own folder, so it never reads or writes the installed app's settings,
/// and may name the providers it shows, in the order it shows them.
public enum AppProfile {
    /// Info.plist key naming the folder under `~` that holds settings, status and history.
    public static let homeDirectoryKey = "ClaudeBarHomeDirectory"
    /// Info.plist key listing the provider ids this build shows, in order.
    public static let providerLineupKey = "ClaudeBarProviderLineup"

    /// The name shown in the app's own header: the bundle's display name
    /// (NabBar for that build), ClaudeBar otherwise.
    public static var displayName: String {
        displayName(info: Bundle.main.infoDictionary)
    }

    /// `~/.claudebar`, or the folder this build's Info.plist names.
    public static var homeDirectory: URL {
        homeDirectory(info: Bundle.main.infoDictionary)
    }

    /// The provider ids this build shows, in order; nil shows every provider.
    public static var providerLineup: [String]? {
        providerLineup(info: Bundle.main.infoDictionary)
    }

    static func displayName(info: [String: Any]?) -> String {
        (info?["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "ClaudeBar"
    }

    static func homeDirectory(info: [String: Any]?) -> URL {
        let name = (info?[homeDirectoryKey] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ".claudebar"
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true)
    }

    static func providerLineup(info: [String: Any]?) -> [String]? {
        guard let ids = info?[providerLineupKey] as? [String], !ids.isEmpty else { return nil }
        return ids
    }

    /// The items a lineup keeps, in the lineup's order. Without a lineup, all of
    /// them in the order given.
    public static func arrange<Item>(_ items: [Item], id: (Item) -> String, lineup: [String]?) -> [Item] {
        guard let lineup else { return items }
        return lineup.compactMap { wanted in items.first { id($0) == wanted } }
    }
}
