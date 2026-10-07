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

    /// Open the create form. `fromClipboard` asks the host to prefill it from the
    /// pasteboard — the same choice the "+" toolbar menu offers — rather than
    /// opening it blank. The *reading* stays in the app: a deep link only states
    /// the intent, so no other process ever touches the pasteboard.
    case createLink(fromClipboard: Bool)

    /// Open the detail screen of a short URL picked from a Spotlight search
    /// result. Unlike ``linkDetail(shortCode:)`` this never comes from a URL —
    /// ``parse(_:)`` doesn't produce it. ``AppModel`` parks it once the link has
    /// been fetched from its server (and that server made active), so the
    /// navigation shell only has to show it.
    case spotlightLink(ShortURL)

    /// Parses a `shlinkly://` URL into a ``DeepLink``.
    ///
    /// Recognised shapes (scheme and host are matched case-insensitively, per
    /// URL rules):
    /// - `shlinkly://link/{shortCode}` → ``linkDetail(shortCode:)``, with a
    ///   non-empty first path segment as the short code.
    /// - `shlinkly://create` → ``createLink(fromClipboard:)`` with `false`.
    /// - `shlinkly://create?source=clipboard` → the same, with `true`.
    ///
    /// Anything else — a foreign scheme, an unknown host, or a missing code —
    /// returns `nil`, so callers can ignore junk URLs safely. An unrecognised
    /// `source` value degrades to the blank form rather than failing.
    public static func parse(_ url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "shlinkly" else {
            return nil
        }

        switch components.host?.lowercased() {
        case "link":
            // `path` is percent-decoded (e.g. "/abc123"); take the first segment.
            let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
            guard let shortCode = segments.first, !shortCode.isEmpty else { return nil }
            return .linkDetail(shortCode: String(shortCode))
        case "create":
            let source = components.queryItems?
                .first { $0.name.lowercased() == "source" }?
                .value?.lowercased()
            return .createLink(fromClipboard: source == "clipboard")
        default:
            return nil
        }
    }
}
