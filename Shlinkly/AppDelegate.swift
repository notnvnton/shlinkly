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

    /// A Dock-icon click (or other reactivation) with no visible windows shows the
    /// main window. Because `applicationShouldTerminateAfterLastWindowClosed`
    /// returns `false`, the app lives on after its window closes, and this is one
    /// route back to it — funnelled through ``showMainWindow()`` like every other.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    /// Apply the saved "menu bar only" preference *before* launch finishes, so the
    /// Dock icon never flickers on for menu-bar-only users. An unset key means
    /// "not menu-bar-only" (the default — Dock + menu bar), so read the raw object
    /// and treat `nil` as `false`. Also start watching for the main window closing,
    /// so the Dock icon can be hidden only once the window is actually gone.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let menuBarOnly = UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// The deferred half of ``applyPresence(menuBarOnly:)``: when the main window
    /// closes while "menu bar only" is on, drop to `.accessory` to finally hide the
    /// Dock icon. Re-checked on the next tick, after the closing window has left
    /// `NSApp.windows`, and only if no main window remains.
    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isMainWindow(window) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let menuBarOnly = UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
                if menuBarOnly && !Self.isMainWindowVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    /// Applies the "menu bar only" preference as an *effective* activation policy.
    ///
    /// The naïve version (`.accessory` whenever the toggle is on) hid the open
    /// window — `.accessory` hides every window *and* bars it from reactivating,
    /// which is why "Open Shlinkly" then did nothing. So while a window is open we
    /// stay `.regular` and defer hiding the Dock until the window closes (handled by
    /// ``mainWindowWillClose(_:)``). Turning the toggle off always returns to
    /// `.regular` and activates.
    static func applyPresence(menuBarOnly: Bool) {
        if menuBarOnly {
            if isMainWindowVisible {
                // Keep the Dock (and the window) until the window is closed.
                NSApp.setActivationPolicy(.regular)
                mainWindow?.canHide = false
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            NSApp.setActivationPolicy(.regular)
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
        // Route through the single show path: it restores the Dock icon (so the
        // window can activate even in menu-bar-only mode) and focuses or reopens the
        // window. If it was closed, `ConfiguredRoot` remounts and consumes
        // `pendingDeepLink` on its initial `onChange`.
        showMainWindow()
    }

    private func flushBufferedDeepLink() {
        guard let appModel, let buffered = bufferedDeepLink else { return }
        appModel.pendingDeepLink = buffered
        bufferedDeepLink = nil
    }

    // MARK: - Showing the window

    /// The single funnel for every "show the window" action — the menu's "Open
    /// Shlinkly", an incoming deep link, and a Dock-icon reopen all route here.
    ///
    /// Restoring the Dock icon (`.regular`) comes *first*: AppKit refuses to make a
    /// window key while the app is `.accessory` (no Dock icon), which is exactly why
    /// "Open Shlinkly" did nothing in menu-bar-only mode. Then we focus the existing
    /// window, or — only if it was closed — reopen the single `Window(id: "main")`
    /// scene, so there's never a second window. Activation is deferred one runloop
    /// tick: doing it inline leaves the window (and the menu) unclickable until the
    /// user changes focus, a known AppKit quirk. (If a test shows the window still
    /// landing behind, add a ~150 ms delay before `makeKeyAndOrderFront`.)
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)

        if Self.mainWindow == nil {
            reopenMainWindow?()
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                let window = Self.mainWindow
                window?.canHide = false   // don't let a later `.accessory` hide it
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Main window

    /// Identifies the app's main `Window` (id `"main"`): the lone titled, non-sheet
    /// window. The menu-bar item's host window and popovers aren't titled, and the
    /// Settings sheet reports `isSheet`, so this picks out the real window. (The
    /// title isn't usable — `navigationTitle` overrides it to the server name.)
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !window.isSheet
    }

    /// The main window if it currently exists (whether or not it's on screen).
    static var mainWindow: NSWindow? {
        NSApp.windows.first { isMainWindow($0) }
    }

    /// Whether the main window currently exists *and* is on screen.
    static var isMainWindowVisible: Bool {
        NSApp.windows.contains { isMainWindow($0) && $0.isVisible }
    }
}
#endif
