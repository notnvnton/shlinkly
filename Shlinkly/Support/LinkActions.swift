//
//  LinkActions.swift
//  Shlinkly
//

import Foundation
import ShlinklyCore

/// App-layer actions on a short URL that aren't tied to a particular view. Kept
/// free of SwiftUI so the same entry points can later back a widget / App Intent
/// without dragging UI code into ``ShlinklyCore`` (which stays UI-free).
enum LinkActions {
    /// Copies a link's full short URL to the system clipboard. The single place
    /// that decides *what* gets copied (the `shortUrl`), so the list rows, the
    /// detail header and a future App Intent all copy the same thing.
    static func copyShortURL(_ shortURL: ShortURL) {
        Clipboard.copy(shortURL.shortUrl)
    }

    /// One-shot creation of a short URL from a long URL, using the active
    /// instance's `client`, with the server defaults (no tags, no custom slug).
    ///
    /// Reuses the Phase 1 create call (``ShlinkClient/createShortURL(_:)``); it
    /// just builds the minimal request. A missing scheme gets `https://`
    /// prepended, matching the create form's `normalizedLongURL` so a pasted
    /// `example.com` resolves the same way here as in the form. Returns the
    /// created ``ShortURL`` (whose `shortUrl` the caller copies); throws on
    /// failure. Shared by the macOS menu bar's "Generate from clipboard" and the
    /// upcoming Share Extension, so they create links identically.
    static func createShortURL(fromLongURL longURL: String, using client: ShlinkClient) async throws -> ShortURL {
        let trimmed = longURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return try await client.createShortURL(CreateShortURLRequest(longUrl: normalized))
    }
}
