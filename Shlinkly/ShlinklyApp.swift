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
        // opens to `AppDelegate.application(_:open:)`. Closing it keeps the app alive
        // (the menu-bar item stays) and only *hides* the window — `WindowAccessor`
        // hands its live `NSWindow` to `MacWindowManager`, which pins it alive and
        // re-shows that same window on "Open" (hide, don't close).
        Window("Shlinkly", id: "main") {
            rootContent
                .background(WindowAccessor { window in
                    MacWindowManager.shared.captureMainWindow(window)
                })
        }

        // A menu-bar dropdown for quick actions, in the same process as the main
        // window so it shares the one active server. The menu-bar item is always
        // present — it's Shlinkly's permanent home; the "menu bar only" setting
        // governs only whether the Dock icon also appears. Because the icon never
        // goes away, a "hidden everywhere" state is structurally unreachable.
        MenuBarExtra {
            MenuBarContent(appModel: appModel)
        } label: {
            MenuBarLabel()
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
/// The menu-bar item's label: the brand chevrons, rendered as a template image.
/// Showing the window is `MacWindowManager`'s job (it re-shows the live window),
/// so this label is purely the icon — no `openWindow`.
private struct MenuBarLabel: View {
    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Shlinkly")
    }
}
#endif
