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

    /// Keep the app running after its last window is closed. The main scene is a
    /// lone `Window`, and AppKit's default is to terminate when the final window
    /// closes — so clicking the window's close button quit the whole app (menu-bar
    /// item and all). Returning `false` keeps the process alive with no windows;
    /// the menu bar's "Open Shlinkly" reopens this same window via `openWindow`.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Apply the saved "Show in Dock" preference *before* launch finishes, so the
    /// Dock icon never flickers on for menu-bar-only users. An unset key means
    /// "show" (the default), so read the raw object and treat `nil` as `true`
    /// rather than letting `UserDefaults`' false-for-missing hide the Dock.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "macShowInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    /// Applies the "Show in Dock" preference to the already-running app, in
    /// response to the Settings toggle. `.regular` shows the Dock icon (and app
    /// switcher entry); `.accessory` hides it, leaving the always-present menu-bar
    /// item as Shlinkly's only presence. When re-showing the Dock icon we also
    /// activate the app, so it (and its window) comes forward with the new icon.
    static func applyDockVisibility(_ showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
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
    }

    private func flushBufferedDeepLink() {
        guard let appModel, let buffered = bufferedDeepLink else { return }
        appModel.pendingDeepLink = buffered
        bufferedDeepLink = nil
    }
}
#endif
