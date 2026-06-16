//
//  AppDelegate.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import ShlinklyCore

/// macOS application delegate — the home for AppKit-level lifecycle bits SwiftUI's
/// scene layer doesn't cover. Right now it routes incoming `shlinkly://` URLs into
/// the app's single `Window`, so a deep link lands in the window that's already
/// open rather than doing nothing (or spawning a second one).
///
/// Shared infrastructure: later phases hang more macOS lifecycle here (e.g. the
/// activation policy), so there's exactly one delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired up by the scene's root `.onAppear`. Optional because AppKit can
    /// deliver a launch URL before the scene appears (a cold open via deep link);
    /// such a link is buffered and flushed the moment this is set.
    var appModel: AppModel? {
        didSet { flushBufferedDeepLink() }
    }

    /// A deep link that arrived before ``appModel`` was wired up (cold launch).
    private var bufferedDeepLink: DeepLink?

    /// Reopens the main window. Captured from the always-mounted menu-bar label
    /// (see `MenuBarLabel` in `ShlinklyApp`): the SwiftUI `openWindow` action stays
    /// valid for reopening the `Window` scene even after the window is closed or
    /// while the app is in accessory (menu-bar-only) mode — whereas the window's
    /// own root view unmounts on close and can't be the capture point. `nil` only
    /// until that label first appears.
    var reopenMainWindow: (() -> Void)?

    /// Keep the app running after its last window is closed. The main scene is a
    /// lone `Window`, and AppKit's default is to terminate when the final window
    /// closes — so clicking the window's close button quit the whole app (menu-bar
    /// item and all). Returning `false` keeps the process alive with no windows;
    /// the menu bar's "Open Shlinkly" reopens this same window via `openWindow`.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock-icon click (or other reactivation) with no visible windows reopens
    /// the main window. Because `applicationShouldTerminateAfterLastWindowClosed`
    /// returns `false`, the app lives on after its window closes, and this is the
    /// route back to it. In accessory (menu-bar-only) mode there's no Dock icon,
    /// but the menu bar's "Open Shlinkly" reaches the same window via the same
    /// reopen path — so it's covered either way.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenMainWindow?()
        }
        return true
    }

    /// Apply the saved "menu bar only" preference *before* launch finishes, so the
    /// Dock icon never flickers on for menu-bar-only users. An unset key means
    /// "not menu-bar-only" (the default — Dock + menu bar), so read the raw object
    /// and treat `nil` as `false`.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let menuBarOnly = UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }

    /// Applies the "menu bar only" preference to the already-running app, in
    /// response to the Settings toggle. `.regular` shows the Dock icon (and app
    /// switcher entry); `.accessory` hides it, leaving the always-present menu-bar
    /// item as Shlinkly's only presence. When the Dock icon returns (`.regular`)
    /// we also activate the app, so it (and its window) comes forward with it.
    static func applyPresence(menuBarOnly: Bool) {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        if !menuBarOnly {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// AppKit delivers `shlinkly://` opens here (the app uses a single `Window`, so
    /// these reach the delegate). We park the parsed link on the shared model — the
    /// open window's navigation shell observes it and selects the link — and bring
    /// that window forward.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let deepLink = DeepLink.parse(url) else { continue }
            if let appModel {
                appModel.pendingDeepLink = deepLink
            } else {
                bufferedDeepLink = deepLink
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        // If the window was closed, the navigation shell (`ConfiguredRoot`) is
        // unmounted and won't consume the parked link — reopen so it remounts,
        // reads `pendingDeepLink` on its initial `onChange`, and navigates.
        if !isMainWindowVisible {
            reopenMainWindow?()
        }
    }

    private func flushBufferedDeepLink() {
        guard let appModel, let buffered = bufferedDeepLink else { return }
        appModel.pendingDeepLink = buffered
        bufferedDeepLink = nil
    }

    /// Whether the main window is currently on screen. The menu-bar item's host
    /// window and any popovers aren't titled, so a visible *titled* window is the
    /// real main `Window`.
    private var isMainWindowVisible: Bool {
        NSApp.windows.contains { $0.styleMask.contains(.titled) && $0.isVisible }
    }
}
#endif
