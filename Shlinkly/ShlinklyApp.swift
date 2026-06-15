//
//  ShlinklyApp.swift
//  Shlinkly
//
//  Created by Anton Hodge on 10.06.26.
//

import SwiftUI
import ShlinklyCore

@main
struct ShlinklyApp: App {
    @State private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    /// Whether the menu-bar icon is shown. Mirrors the Settings toggle through
    /// the shared `UserDefaults` key, and drives ``MenuBarExtra``'s `isInserted`.
    /// Defaults to on. Hiding it removes only the menu-bar item — the
    /// `WindowGroup` keeps the app alive, so the app doesn't quit.
    @AppStorage("shlinkly.showInMenuBar") private var showInMenuBar = true
    #endif

    init() {
        let model = AppModel()
        // Credentials come from Keychain-backed instances: bootstrap brings the
        // active server online, or leaves the app in onboarding when none exist.
        model.bootstrap()
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        // Explicit id so the macOS menu bar's "Open Shlinkly" can target this
        // window; harmless on iOS.
        WindowGroup(id: "main") {
            RootView()
                .environment(appModel)
                // The servers live in the (iCloud-synced) Keychain, which has no
                // live change notification — so re-read it whenever the app comes
                // to the foreground. A server added with iCloud sync on another
                // device appears here on this activation.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appModel.refreshFromStore()
                    }
                }
        }

        #if os(macOS)
        // A menu-bar dropdown for quick actions, in the same process as the main
        // window so it shares the one active server. `isInserted` is bound to the
        // Settings toggle, so unchecking it hides the icon without quitting.
        MenuBarExtra("Shlinkly", systemImage: "link", isInserted: $showInMenuBar) {
            MenuBarContent(appModel: appModel)
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}
