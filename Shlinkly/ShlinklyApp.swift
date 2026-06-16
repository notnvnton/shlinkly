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
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    /// macOS app delegate. It *owns* the main window — created in AppKit with an
    /// `NSHostingController` wrapping the SwiftUI root — routes `shlinkly://` deep
    /// links, and manages the activation policy. There is deliberately no SwiftUI
    /// `Window`/`WindowGroup` scene on macOS: owning the `NSWindow` ourselves is what
    /// finally makes show / hide / reopen reliable (SwiftUI's `openWindow` no-ops
    /// once a scene's render tree has been torn down).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Bring the shared model online once: credentials come from Keychain-backed
        // instances, or the app stays in onboarding when none exist.
        AppModel.shared.bootstrap()
    }

    var body: some Scene {
        #if os(macOS)
        // No `Window` scene — `AppDelegate` creates and holds the main window. The
        // Settings scene keeps ⌘, (and the app-menu item) working; the menu-bar item
        // is Shlinkly's always-present home. The model is injected explicitly here
        // because environment doesn't cross into a separate scene's hosting view.
        Settings {
            SettingsView()
                .environment(AppModel.shared)
        }

        MenuBarExtra {
            MenuBarContent(appModel: AppModel.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
        #else
        WindowGroup(id: "main") {
            RootView()
                .environment(AppModel.shared)
                // The servers live in the (iCloud-synced) Keychain, which has no live
                // change notification — so re-read it whenever the app comes to the
                // foreground. A server added with iCloud sync on another device
                // appears here on this activation.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        AppModel.shared.refreshFromStore()
                    }
                }
                // shlinkly://link/{shortCode} → land on that link's detail. iOS has no
                // duplicate-window issue, so SwiftUI's URL handler is used as-is; it
                // parks the parsed link and the navigation shell consumes it. Junk
                // URLs parse to nil and are ignored.
                .onOpenURL { url in
                    if let deepLink = DeepLink.parse(url) {
                        AppModel.shared.pendingDeepLink = deepLink
                    }
                }
        }
        #endif
    }
}

#if os(macOS)
/// The menu-bar item's label: the brand chevrons, rendered as a template image.
/// Showing the window is the AppDelegate's job (it holds the live `NSWindow` and
/// shows it via AppKit), so this label is purely the icon.
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
