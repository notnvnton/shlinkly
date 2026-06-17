//
//  AppDelegate.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import ShlinklyCore
import os

/// macOS application delegate — the AppKit-level lifecycle SwiftUI's scene layer
/// doesn't cover: routing `shlinkly://` deep links, keeping the app alive when its
/// window is closed, and owning the menu-bar status item.
///
/// Window *showing* is not here: it's ``MacWindowManager``, which owns the live
/// `NSWindow` captured via ``WindowAccessor`` and re-shows it (hide, don't close).
/// The delegate only forwards "please show" to that single path.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "de.ahodge.shlinkly", category: "WindowLifecycle")

    /// Wired up by the scene's root `.onAppear`. Optional because AppKit can deliver
    /// a launch URL before the scene appears (a cold open via deep link); such a link
    /// is buffered and flushed the moment this is set. Setting it is also what spins
    /// up the menu bar, with the *same* model instance the rest of the app uses.
    var appModel: AppModel? {
        didSet {
            flushBufferedDeepLink()
            startMenuBarIfNeeded()
        }
    }

    /// A deep link that arrived before ``appModel`` was wired up (cold launch).
    private var bufferedDeepLink: DeepLink?

    /// The menu-bar status item's controller, owned here for the app's lifetime.
    /// Created once, from the injected ``appModel`` (no singleton model).
    private var menuBarController: MenuBarController?

    // MARK: - Keeping the app alive

    /// Closing the main window never quits the app — the menu-bar item (and its
    /// "Generate from clipboard") is the whole point of staying resident. Quitting is
    /// only ever via the menu-bar "Quit". The Dock-presence decision on close lives
    /// in ``MacWindowManager`` (driven by the window's `willClose`), not here.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        log.info("terminate? returning false")
        return false
    }

    /// Reactivating the app (a Dock click when present, ⌘-tab, or the menu-bar
    /// "Open") restores the regular activation policy so the Dock icon comes back.
    func applicationWillBecomeActive(_ notification: Notification) {
        log.info("willBecomeActive → .regular")
        NSApp.setActivationPolicy(.regular)
    }

    // MARK: - Deep links

    /// AppKit delivers `shlinkly://` opens here. Park the parsed link on the shared
    /// model (or buffer it until the model is wired), then show the window via the
    /// single path so the navigation shell is visible to consume it. `appModel` is
    /// app-level, so it survives the window being hidden and re-shown.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let deepLink = DeepLink.parse(url) else { continue }
            if let appModel {
                appModel.pendingDeepLink = deepLink
            } else {
                bufferedDeepLink = deepLink
            }
        }
        MacWindowManager.shared.showMainWindow()
    }

    private func flushBufferedDeepLink() {
        guard let appModel, let buffered = bufferedDeepLink else { return }
        appModel.pendingDeepLink = buffered
        bufferedDeepLink = nil
    }

    // MARK: - Menu bar

    /// Spins up the menu-bar status item once, when ``appModel`` is first wired. The
    /// controller takes that exact instance, so the menu reads the one active server
    /// the app is already using.
    private func startMenuBarIfNeeded() {
        guard menuBarController == nil, let appModel else { return }
        menuBarController = MenuBarController(appModel: appModel)
    }
}
#endif
