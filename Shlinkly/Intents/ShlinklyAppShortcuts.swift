//
//  ShlinklyAppShortcuts.swift
//  Shlinkly
//

import AppIntents

/// Registers the app's intents with Shortcuts and Siri on install, so
/// "Create short link" is discoverable without the user wiring anything up.
struct ShlinklyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateShortLinkIntent(),
            phrases: [
                "Create a short link with \(.applicationName)",
                "Shorten a link with \(.applicationName)",
            ],
            shortTitle: "Create short link",
            systemImageName: "link"
        )
    }
}
