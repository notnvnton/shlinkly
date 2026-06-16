//
//  AppDelegate.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import SwiftUI
import ShlinklyCore

/// macOS application delegate — it **owns** the main window.
///
/// Instead of a SwiftUI `Window` scene (which we couldn't reliably identify, keep
/// our delegate on, or reopen once its render tree was torn down), the window is a
/// plain `NSWindow` we create and hold here, hosting the SwiftUI root via
/// `NSHostingController`. Closing it only *hides* it (`orderOut`); we show it again
/// directly with AppKit. This is the standard menu-bar-app pattern and makes
/// show / hide / reopen deterministic.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// The main window, created in ``applicationDidFinishLaunching`` and never
    /// destroyed (the close button only hides it). Implicitly unwrapped because it
    /// exists for the whole post-launch lifetime; `makeMainWindowIfNeeded()` guards
    /// the rare early path.
    var mainWindow: NSWindow!

    // MARK: - Launch

    /// Set the saved activation policy before any window exists, so the Dock icon
    /// doesn't flicker on for menu-bar-only users.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.menuBarOnly ? .accessory : .regular)
    }

    /// Create the window we own, then present the start state: menu-bar-only starts
    /// hidden with no Dock icon; the default mode starts visible in the Dock.
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMainWindowIfNeeded()
        if Self.menuBarOnly {
            mainWindow.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    /// The servers live in the iCloud-synced Keychain (no live change notification),
    /// so re-read on every activation — the macOS equivalent of the scene's former
    /// `scenePhase == .active` refresh.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshFromStore()
    }

    /// Build the `NSWindow` that hosts the SwiftUI root. Environment does **not**
    /// cross the `NSHostingController` boundary, so the shared `AppModel` is injected
    /// explicitly — it's the only custom environment value the view tree reads.
    private func makeMainWindowIfNeeded() {
        guard mainWindow == nil else { return }

        let hosting = NSHostingController(rootView: RootView().environment(AppModel.shared))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Shlinkly"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.canHide = false
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.center()
        window.setFrameAutosaveName("ShlinklyMain")
        mainWindow = window
    }

    // MARK: - Keeping the app alive

    /// Insurance: with hide-on-close the window never actually closes, so this can't
    /// fire — but keep the app alive regardless.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock-icon click (or other reactivation) with no visible windows shows the
    /// main window — funnelled through ``showMainWindow()`` like every other path.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Hide on close

    /// The red close button *hides* the window instead of closing it: `orderOut`
    /// keeps the `NSWindow` (and its SwiftUI render tree) alive so we can show it
    /// again, and `false` cancels the real close. This is *our* delegate on *our*
    /// window, so it always fires. In menu-bar-only mode, hiding is also when the
    /// Dock icon finally goes away.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        mainWindow.orderOut(nil)
        if Self.menuBarOnly {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    // MARK: - Showing the window

    /// The single funnel for every "show the window" action — the menu's "Open
    /// Shlinkly", an incoming deep link, and a Dock-icon reopen all route here.
    ///
    /// Restoring the Dock icon (`.regular`) comes first: AppKit refuses to make a
    /// window key while `.accessory`. Then we show our held window directly with
    /// AppKit. Activation is repeated on the next runloop tick to dodge the AppKit
    /// quirk where an inline activate leaves the window unclickable until refocus.
    func showMainWindow() {
        makeMainWindowIfNeeded()
        NSApp.setActivationPolicy(.regular)
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.delegate as? AppDelegate)?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Deep links

    /// AppKit delivers `shlinkly://` opens here. Park the parsed link on the shared
    /// model — the navigation shell observes it and selects the link — then show the
    /// (possibly hidden) window. Because the window is only hidden, its render tree
    /// is alive and consumes `pendingDeepLink` on the next observation pass.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let deepLink = DeepLink.parse(url) else { continue }
            AppModel.shared.pendingDeepLink = deepLink
        }
        showMainWindow()
    }

    // MARK: - Presence (Dock-aware activation policy)

    /// Applies the "menu bar only" preference as an *effective* activation policy,
    /// called from the Settings toggle. A visible window always implies `.regular`
    /// (a window can't live without a Dock icon); only once the window is hidden does
    /// menu-bar-only actually drop the Dock. The window is ours, so `isVisible` is
    /// authoritative.
    static func applyPresence(menuBarOnly: Bool) {
        let windowVisible = (NSApp.delegate as? AppDelegate)?.mainWindow?.isVisible ?? false
        if windowVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        }
    }

    /// Whether "menu bar only" is enabled (unset → `false`, i.e. Dock + menu bar).
    static var menuBarOnly: Bool {
        UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
    }
}
#endif
