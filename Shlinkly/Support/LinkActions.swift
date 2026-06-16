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
    /// A thin app-side wrapper: the normalisation + create logic now lives in
    /// ``ShlinkClient/createShortURL(fromLongURL:)`` in ``ShlinklyCore`` so the
    /// app and both Share Extensions create links identically. Returns the
    /// created ``ShortURL`` (whose `shortUrl` the caller copies); throws on
    /// failure. Shared by the macOS menu bar's "Generate from clipboard" and the
    /// Share Extension.
    static func createShortURL(fromLongURL longURL: String, using client: ShlinkClient) async throws -> ShortURL {
        try await client.createShortURL(fromLongURL: longURL)
    }
}
