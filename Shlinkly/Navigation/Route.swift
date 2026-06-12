//
//  Route.swift
//  Shlinkly
//

import ShlinklyCore

/// Typed navigation destinations within the app.
///
/// Carries the whole ``ShortURL`` value so the detail screen can render its
/// metadata immediately (the visits are fetched on arrival). `ShortURL` is
/// `Hashable`, so this drives both the iOS `NavigationStack` and the macOS
/// `NavigationSplitView` selection.
enum Route: Hashable {
    case shortURLDetail(ShortURL)
}
