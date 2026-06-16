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
