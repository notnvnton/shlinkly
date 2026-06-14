//
//  Clipboard.swift
//  Shlinkly
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Thin cross-platform wrapper over the system pasteboard.
enum Clipboard {
    /// Copies `string` to the general pasteboard, replacing its contents.
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }

    /// Whether the pasteboard *probably* holds a URL — determined without reading
    /// (and thus revealing) the contents, so it never triggers the iOS "pasted
    /// from" banner. The value is only read when the user taps "Paste from
    /// clipboard".
    ///
    /// On iOS a plain-text URL isn't reported by `hasURLs` (that's only typed URL
    /// items), so we fall back to `detectPatterns(for: .probableWebURL)`, which
    /// inspects the pattern without exposing the contents.
    static func containsProbableURL() async -> Bool {
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        if pasteboard.hasURLs { return true }
        guard pasteboard.hasStrings else { return false }
        let target: UIPasteboard.DetectionPattern = .probableWebURL
        return await withCheckedContinuation { continuation in
            pasteboard.detectPatterns(for: [target]) { result in
                switch result {
                case .success(let patterns):
                    continuation.resume(returning: patterns.contains(target))
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
        #elseif os(macOS)
        guard let string = NSPasteboard.general.string(forType: .string) else { return false }
        return looksLikeURL(string)
        #endif
    }

    /// Reads a URL-looking string from the pasteboard, or `nil`. This *does*
    /// access the contents, so only call it in response to an explicit user tap.
    static func peekURLString() -> String? {
        #if os(iOS)
        if let url = UIPasteboard.general.url { return url.absoluteString }
        if let string = UIPasteboard.general.string, looksLikeURL(string) { return string }
        return nil
        #elseif os(macOS)
        guard let string = NSPasteboard.general.string(forType: .string), looksLikeURL(string) else {
            return nil
        }
        return string
        #endif
    }

    /// A loose "could be a URL" check: a single token with a dot in it.
    private static func looksLikeURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
        return trimmed.contains(".")
    }
}
