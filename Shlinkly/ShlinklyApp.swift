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
    /// macOS app delegate. Handles incoming `shlinkly://` URLs at the AppKit level
    /// so a deep link routes into the existing window instead of `WindowGroup`
    /// opening a second one. Also the home for future macOS lifecycle bits.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        #if os(macOS)
        // A single `Window` (not `WindowGroup`): macOS should never have two main
        // windows, and crucially a lone window lets AppKit deliver `shlinkly://`
        // opens to `AppDelegate.application(_:open:)`. A `WindowGroup` with
        // `.handlesExternalEvents(matching: [])` swallowed those URLs, so "Open in
        // Shlinkly" did nothing — the regression this fixes. The menu bar's
        // `openWindow(id: "main")` still opens/focuses this same window.
        Window("Shlinkly", id: "main") {
            rootContent
        }

        // A menu-bar dropdown for quick actions, in the same process as the main
        // window so it shares the one active server. `isInserted` reflects the
        // Settings toggle (via `menuBarInsertion`), so unchecking it hides the
        // icon without quitting.
        MenuBarExtra("Shlinkly", systemImage: "link", isInserted: menuBarInsertion) {
            MenuBarContent(appModel: appModel)
        }
        .menuBarExtraStyle(.menu)
        #else
        // Explicit id keeps parity with the macOS window; harmless on iOS.
        WindowGroup(id: "main") {
            rootContent
        }
        #endif
    }

    /// The shared root content for the main scene on both platforms.
    private var rootContent: some View {
        RootView()
            .environment(appModel)
            // The servers live in the (iCloud-synced) Keychain, which has no live
            // change notification — so re-read it whenever the app comes to the
            // foreground. A server added with iCloud sync on another device appears
            // here on this activation.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    appModel.refreshFromStore()
                }
            }
            #if os(iOS)
            // shlinkly://link/{shortCode} → land on that link's detail. iOS has no
            // duplicate-window issue, so SwiftUI's URL handler is used as-is; it
            // parks the parsed link and the navigation shell consumes it. Junk URLs
            // parse to nil and are ignored.
            .onOpenURL { url in
                if let deepLink = DeepLink.parse(url) {
                    appModel.pendingDeepLink = deepLink
                }
            }
            #else
            // macOS routes deep links through the AppDelegate (so they land in the
            // existing window). Wire the delegate to the shared model once the
            // scene is up.
            .onAppear { appDelegate.appModel = appModel }
            #endif
    }

    #if os(macOS)
    /// The `isInserted` binding for the menu-bar item.
    ///
    /// `MenuBarExtra` syncs its live insertion state *back* through this binding
    /// during scene updates. Passing `$showInMenuBar` (an `@AppStorage`) straight
    /// in means that write-back hits `UserDefaults` **mid view-update**, which
    /// publishes a change that re-invalidates this scene, which re-renders and
    /// writes the same value again — an unbounded "Publishing changes from within
    /// view updates" loop that pegs the main thread and hangs the app on launch.
    /// Guarding so we only write on an *actual* change (the redundant launch-time
    /// write-back never is one) breaks the cycle, while the Settings toggle still
    /// flips the stored value to show/hide the icon.
    private var menuBarInsertion: Binding<Bool> {
        let stored = $showInMenuBar
        return Binding(
            get: { stored.wrappedValue },
            set: { newValue in
                if newValue != stored.wrappedValue { stored.wrappedValue = newValue }
            }
        )
    }
    #endif
}
