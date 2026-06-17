//
//  MacWindowManager.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import os

/// The single owner of the main window's `NSWindow`, and the single source of the
/// "hide, don't close" lifecycle.
///
/// Earlier attempts tried to *resurrect* a destroyed `Window` (via `openWindow`,
/// `NSWorkspace.openApplication`, searching `NSApp.windows` by title, an
/// AppKit-owned `NSHostingController`, …) and all failed. The model here is the
/// opposite: the window is never destroyed. ``WindowAccessor`` hands us the live
/// `NSWindow` once; we set `isReleasedWhenClosed = false` and keep the only strong
/// reference. Closing it merely orders it out — showing it again just orders the
/// same live window back to front. There is nothing to resurrect.
@MainActor
final class MacWindowManager {
    /// The one owner. The single place a reference to the main window is held.
    static let shared = MacWindowManager()

    private let log = Logger(subsystem: "de.ahodge.shlinkly", category: "WindowLifecycle")

    /// The one and only strong reference to the main window. Kept alive across
    /// closes (`isReleasedWhenClosed = false`) so "open" is a re-show, not a rebuild.
    private var mainWindow: NSWindow?

    private init() {}

    // MARK: - Capture

    /// Wired up from ``WindowAccessor`` when the main window's `NSWindow` first
    /// appears. Pins the window alive, stores the sole strong reference, and starts
    /// observing *this* window's close (the observer is filtered to our reference so
    /// a stray panel/popover close can never trigger the policy change).
    func captureMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        log.info("captured main window: true, frame=\(NSStringFromRect(window.frame), privacy: .public)")
    }

    // MARK: - Close → policy

    /// Fires when *our* window is about to close. The window orders itself out (it is
    /// not destroyed); we only adjust the Dock presence to match the user's setting.
    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        applyPolicyForClosedWindow()
    }

    /// On close, the activation policy reflects the "menu bar only" setting: hidden
    /// from the Dock (`.accessory`) when on, present in the Dock (`.regular`) when
    /// off. The app stays alive either way — the menu-bar item is its home.
    func applyPolicyForClosedWindow() {
        let menuBarOnly = UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
        let policy: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        log.info("main window willClose; menuBarOnly=\(menuBarOnly) → policy=\(policy == .accessory ? "accessory" : "regular", privacy: .public)")
        NSApp.setActivationPolicy(policy)
    }

    // MARK: - Show

    /// The single way to bring the window to the front — used by both the menu-bar
    /// "Open Shlinkly" item and an incoming deep link. No `openWindow` /
    /// `openApplication`: we order *our* live window forward, restoring the Dock
    /// icon first so the app is a normal foreground app while its window is visible.
    func showMainWindow() {
        log.info("showMainWindow called; haveWindow=\(self.mainWindow != nil)")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window = mainWindow else { return }
        window.makeKeyAndOrderFront(nil)
        log.info("ordered front; isVisible=\(window.isVisible)")
    }
}
#endif
