//
//  AppDelegate.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import ShlinklyCore

/// macOS application delegate — the AppKit-level lifecycle SwiftUI's scene layer
/// doesn't cover: routing `shlinkly://` deep links, keeping the app alive when its
/// window is closed, and showing the window again.
///
/// The window itself is an ordinary SwiftUI `Window` scene — we do **not** own an
/// `NSWindow`. Showing it is done the way working menu-bar apps (e.g. Passepartout)
/// do it: ask the system to reopen our app instance (`NSWorkspace.openApplication`),
/// which brings the app to `.regular`, recreates the window, and restores the Dock
/// icon — no manual `makeKeyAndOrderFront` / `setActivationPolicy`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired up by the scene's root `.onAppear`. Optional because AppKit can deliver
    /// a launch URL before the scene appears (a cold open via deep link); such a link
    /// is buffered and flushed the moment this is set.
    var appModel: AppModel? {
        didSet { flushBufferedDeepLink() }
    }

    /// A deep link that arrived before ``appModel`` was wired up (cold launch).
    private var bufferedDeepLink: DeepLink?

    // MARK: - Keeping the app alive

    /// Closing the main window never quits the app — the menu-bar item (and its
    /// "Generate from clipboard") is the whole point of staying resident. In
    /// menu-bar-only mode, the window closing is also when the Dock icon goes away;
    /// otherwise the Dock icon stays and a Dock click reopens the window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if Self.menuBarOnly {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    // MARK: - Showing the window

    /// The single way to show the window: ask the system to reopen our (already
    /// running) app instance. macOS restores `.regular`, recreates the `Window`
    /// scene's window, and brings everything forward. This is the Passepartout
    /// pattern — a closed SwiftUI `Window` can't be reopened with `openWindow`, but
    /// the system's own reopen does it reliably, with no AppKit window poking.
    func showMainWindow() {
        Task { @MainActor in
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = false
            try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
        }
    }

    // MARK: - Deep links

    /// AppKit delivers `shlinkly://` opens here. Park the parsed link on the shared
    /// model (or buffer it until the model is wired), then ask the system to show the
    /// window so the navigation shell mounts and consumes it. `appModel` is app-level,
    /// so it survives the window being destroyed and recreated.
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

    // MARK: - Preference

    /// Whether "menu bar only" is enabled (unset → `false`, i.e. Dock + menu bar).
    /// Read only on window close, to decide whether the Dock icon should go away.
    private static var menuBarOnly: Bool {
        UserDefaults.standard.object(forKey: "macMenuBarOnly") as? Bool ?? false
    }
}
#endif
