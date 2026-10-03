import Foundation

/// What a `nabbar://` URL asks the app to do.
///
/// Only the exact documented URLs are actions: `nabbar://open`,
/// `nabbar://refresh`, `nabbar://settings`, and their three-slash
/// spelling (`nabbar:///open`). The URL is compared as a whole string, so
/// anything else, whether a parameter, a fragment, a user, a port or an extra
/// path, is not an action. See docs/features/url-schemes/README.md.
enum URLSchemeAction: String, Equatable, Sendable, CaseIterable {
    case open
    case refresh
    case settings

    static let scheme = "nabbar"

    /// The exact URL strings that name this action.
    var acceptedURLStrings: Set<String> {
        ["\(Self.scheme)://\(rawValue)", "\(Self.scheme):///\(rawValue)"]
    }

    init?(url: URL) {
        let string = url.absoluteString.lowercased()
        guard let action = Self.allCases.first(where: { $0.acceptedURLStrings.contains(string) }) else {
            return nil
        }
        self = action
    }
}
