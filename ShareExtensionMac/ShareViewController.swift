//
//  ShareViewController.swift
//  ShareExtensionMac
//

import AppKit
import SwiftUI

/// Thin host: pulls the shared URL out of the extension context, then hosts the
/// shared ``ShareCreateView`` (which does the resolve + create) in an
/// `NSHostingController` pinned to the edges, sized for a share popover.
/// `onDone` completes the request. Programmatic — no xib (`loadView` builds the
/// view), so the template `nibName` is gone.
class ShareViewController: NSViewController {

    // Tall enough that the success state (the tallest) fits without clipping —
    // checkmark, "ready" line, URL field, copied note, and the action buttons,
    // all with padding. The old 360x220 cropped the top/bottom on device.
    private static let contentSize = NSSize(width: 380, height: 400)

    /// Held while the share menu is open so the picker isn't deallocated mid-display.
    private var sharingPicker: NSSharingServicePicker?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = Self.contentSize
        Task { @MainActor in
            let longURL = await ShareItemReader.extractURL(from: extensionContext)
            present(longURL: longURL)
        }
    }

    @MainActor
    private func present(longURL: String?) {
        // No URL in the share → nothing to do; close cleanly rather than crash.
        guard let longURL else { complete(); return }

        let host = NSHostingController(
            rootView: ShareCreateView(
                longURL: longURL,
                onDone: { [weak self] in self?.complete() },
                onOpenInApp: { [weak self] url in self?.open(url) },
                onShare: { [weak self] url in self?.share(url) }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Launches the main app with the deep link, then closes the extension.
    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        complete()
    }

    /// Presents the system share menu (Messages, Mail, AirDrop, third-party apps)
    /// for the short URL, anchored to the host view. Used instead of SwiftUI
    /// `ShareLink`, which comes up empty in a sandboxed macOS share extension. The
    /// extension stays open afterwards so the user can still tap Done.
    private func share(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        sharingPicker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
