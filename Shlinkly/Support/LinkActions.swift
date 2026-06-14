//
//  LinkActions.swift
//  Shlinkly
//

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
}
