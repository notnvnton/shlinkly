//
//  AppDelegate.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import ShlinklyCore

/// macOS application delegate — owns the AppKit-level window lifecycle that
/// SwiftUI's scene layer handles unreliably.
///
/// The core decision: the main `Window` is **never destroyed**. Closing it (the
/// red button) only *hides* it (`orderOut`); we keep a live `NSWindow` reference
/// and show it again directly with AppKit's `makeKeyAndOrderFront`. This sidesteps
/// SwiftUI's `openWindow`, which silently no-ops once a `Window` scene's render
/// tree has been torn down (notably on recent macOS) — the root cause of "Open
/// Shlinkly" doing nothing and the window being unrecoverable after the close
/// button. A window also can't be activated without a Dock icon, so every show
/// restores `.regular` first.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Wired up by the scene's root `.onAppear`. Optional because AppKit can
    /// deliver a launch URL before the scene appears (a cold open via deep link);
    /// such a link is buffered and flushed the moment this is set.
    var appModel: AppModel? {
        didSet { flushBufferedDeepLink() }
    }

    /// A deep link that arrived before ``appModel`` was wired up (cold launch).
    private var bufferedDeepLink: DeepLink?

    /// The live reference to the single main `Window`. Held so we can show it via
    /// AppKit directly — the window is only hidden, never closed, so it stays valid.
    var mainWindow: NSWindow?

    // MARK: - Launch

    /// Set the saved activation policy early so the Dock icon doesn't flicker on
    /// for menu-bar-only users (no windows exist yet at this point).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.menuBarOnly ? .accessory : .regular)
    }

    /// Once SwiftUI has created the window, take it over — become its delegate (to
    /// intercept the close button) and pin `canHide`/`isReleasedWhenClosed` — and
    /// apply the start state. Re-assert ownership whenever the window becomes main,
    /// in case SwiftUI re-sets the delegate. The window may not exist on the first
    /// pass, so retry on the next runloop tick.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        acquireMainWindowThenStart(attempt: 0)
    }

    private func acquireMainWindowThenStart(attempt: Int) {
        if ensureMainWindow() != nil {
            applyStartState()
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.acquireMainWindowThenStart(attempt: attempt + 1)
            }
        }
    }

    /// Launch presentation: menu-bar-only starts hidden with no Dock icon; the
    /// default mode starts visible in the Dock.
    private func applyStartState() {
        if Self.menuBarOnly {
            mainWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// Re-assert our ownership of the window whenever it becomes main — cheap
    /// insurance against SwiftUI re-installing its own delegate after launch, which
    /// would otherwise let a close button actually destroy the window.
    @objc private func mainWindowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              Self.isMainWindowCandidate(window) else { return }
        if mainWindow == nil { mainWindow = window }
        configure(window)
    }

    // MARK: - Keeping the app alive

    /// Insurance only: with hide-on-close the window never actually closes, so the
    /// "last window closed" termination can't fire — but keep the app alive anyway.
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
    /// keeps the `NSWindow` (and SwiftUI's render tree) alive so we can show it
    /// again, and `false` cancels the real close. In menu-bar-only mode, hiding the
    /// window is also when the Dock icon finally goes away.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
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
    /// window key while `.accessory`. Then we show the held window directly with
    /// AppKit (`makeKeyAndOrderFront` + `orderFrontRegardless`) — no SwiftUI
    /// `openWindow`. Activation is repeated on the next runloop tick to dodge the
    /// AppKit quirk where an inline activate leaves the window unclickable until the
    /// user changes focus.
    func showMainWindow() {
        let window = ensureMainWindow()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.delegate as? AppDelegate)?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Deep links

    /// AppKit delivers `shlinkly://` opens here (a lone `Window`, so these reach the
    /// delegate). Park the parsed link on the shared model — the window's navigation
    /// shell observes it and selects the link — then show the (possibly hidden)
    /// window. Because the window is only hidden, its render tree is alive and
    /// consumes `pendingDeepLink` on the next observation pass.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let deepLink = DeepLink.parse(url) else { continue }
            if let appModel {
                appModel.pendingDeepLink = deepLink
            } else {
                bufferedDeepLink = deepLink
            }
        }
        showMainWindow()
    }

    private func flushBufferedDeepLink() {
        guard let appModel, let buffered = bufferedDeepLink else { return }
        appModel.pendingDeepLink = buffered
        bufferedDeepLink = nil
    }

    // MARK: - Presence (Dock-aware activation policy)

    /// Applies the "menu bar only" preference as an *effective* activation policy,
    /// called from the Settings toggle. A visible window always implies `.regular`
    /// (a window can't live without a Dock icon); only once the window is hidden
    /// does menu-bar-only actually drop the Dock.
    static func applyPresence(menuBarOnly: Bool) {
        let windowVisible = (NSApp.delegate as? AppDelegate)?.mainWindow?.isVisible ?? false
        if windowVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        }
    }

    // MARK: - Main window lookup

    /// Whether "menu bar only" is enabled (unset → `false`, i.e. Dock + menu bar).
    static var menuBarOnly: Bool {
        UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
    }

    /// Ensure ``mainWindow`` points at the live main window and is configured as our
    /// delegate. Re-asserts the delegate/flags on every call in case SwiftUI re-set
    /// them. Returns `nil` only when the window doesn't exist yet (very early launch).
    @discardableResult
    private func ensureMainWindow() -> NSWindow? {
        if let window = mainWindow, NSApp.windows.contains(where: { $0 === window }) {
            configure(window)
            return window
        }
        guard let found = Self.findMainWindow() else { return nil }
        mainWindow = found
        configure(found)
        return found
    }

    /// Take ownership of the window: intercept its close button, keep it from being
    /// hidden by `.accessory`, and keep the object alive across a stray close.
    private func configure(_ window: NSWindow) {
        if window.delegate !== self { window.delegate = self }
        window.canHide = false
        window.isReleasedWhenClosed = false
    }

    /// Find the main `Window` among `NSApp.windows`: SwiftUI's scene `identifier`
    /// `"main"` first, then the `"Shlinkly"` title, then the lone titled, non-sheet,
    /// non-panel window (the title is otherwise overridden by `navigationTitle`, so
    /// the structural fallback is what actually carries most launches).
    private static func findMainWindow() -> NSWindow? {
        let windows = NSApp.windows
        if let byID = windows.first(where: { $0.identifier?.rawValue == "main" }) {
            return byID
        }
        if let byTitle = windows.first(where: { $0.title == "Shlinkly" }) {
            return byTitle
        }
        return windows.first(where: isMainWindowCandidate)
    }

    /// Whether a window looks like the main content window: titled, not a sheet,
    /// not a panel (the menu-bar item's host window and popovers are panels).
    private static func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !window.isSheet && !(window is NSPanel)
    }
}
#endif
