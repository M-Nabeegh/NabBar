import Foundation

/// Which build of the app this is, read from its Info.plist.
///
/// NabBar's Info.plist names its folder (`~/.nabbar`) and the providers it shows,
/// in order. Without those keys the folder is still `~/.nabbar`, so NabBar never
/// reads or writes an installed ClaudeBar's `~/.claudebar`, and every provider shows.
public enum AppProfile {
    /// Info.plist key naming the folder under `~` that holds settings, status and history.
    public static let homeDirectoryKey = "NabBarHomeDirectory"
    /// Info.plist key listing the provider ids this build shows, in order.
    public static let providerLineupKey = "NabBarProviderLineup"

    /// The name shown in the app's own header: the bundle's display name, else NabBar.
    public static var displayName: String {
        displayName(info: Bundle.main.infoDictionary)
    }

    /// `~/.nabbar`, or the folder this build's Info.plist names.
    public static var homeDirectory: URL {
        homeDirectory(info: Bundle.main.infoDictionary)
    }

    /// The provider ids this build shows, in order; nil shows every provider.
    public static var providerLineup: [String]? {
        providerLineup(info: Bundle.main.infoDictionary)
    }

    static func displayName(info: [String: Any]?) -> String {
        (info?["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "NabBar"
    }

    static func homeDirectory(info: [String: Any]?) -> URL {
        let name = (info?[homeDirectoryKey] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ".nabbar"
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
