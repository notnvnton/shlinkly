import Foundation

/// A parsed `shlinkly://` deep link.
///
/// UI-free and self-contained so the same parser backs the app's `onOpenURL`
/// today and future entry points (Spotlight, Shortcuts/App Intents, widgets)
/// without dragging in any navigation code. Designed to grow: new link shapes
/// add cases here, and every caller switches over them.
public enum DeepLink: Equatable, Sendable {
    /// Open a single short URL's detail screen, identified by its short code.
    case linkDetail(shortCode: String)

    /// Parses a `shlinkly://link/{shortCode}` URL into a ``DeepLink``.
    ///
    /// Matches `scheme == "shlinkly"` and `host == "link"` (both case-insensitive,
    /// per URL rules) with a non-empty first path segment as the short code.
    /// Anything else — a foreign scheme, the wrong host, or a missing code —
    /// returns `nil`, so callers can ignore junk URLs safely.
    public static func parse(_ url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "shlinkly",
              components.host?.lowercased() == "link" else {
            return nil
        }
        // `path` is percent-decoded (e.g. "/abc123"); take the first segment.
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let shortCode = segments.first, !shortCode.isEmpty else { return nil }
        return .linkDetail(shortCode: String(shortCode))
    }
}
