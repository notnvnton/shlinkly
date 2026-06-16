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
        // window so it shares the one active server. The menu-bar item is always
        // present — it's Shlinkly's permanent home; the "menu bar only" setting
        // governs only whether the Dock icon also appears. Because the icon never
        // goes away, a "hidden everywhere" state is structurally unreachable.
        //
        // A custom label (vs. the title+image initializer) lets it capture the
        // `openWindow` action and hand the AppDelegate a way to reopen the main
        // window after it's closed (or in accessory mode).
        MenuBarExtra {
            MenuBarContent(appModel: appModel)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
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
}

#if os(macOS)
/// The menu-bar item's label. A `View` (rather than the title+image
/// `MenuBarExtra` initializer) so it can read `openWindow` from its environment
/// and stash a reopen closure on the AppDelegate. The menu-bar item is always
/// mounted, so this fires once and the captured action stays valid for reopening
/// the main `Window` even after it's closed or while the app is in accessory
/// (menu-bar-only) mode — where the window's own root view is unmounted.
private struct MenuBarLabel: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Shlinkly")
            .onAppear {
                appDelegate.reopenMainWindow = { openWindow(id: "main") }
            }
    }
}
#endif
