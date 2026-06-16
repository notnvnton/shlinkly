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

    private static let contentSize = NSSize(width: 360, height: 220)

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
            rootView: ShareCreateView(longURL: longURL) { [weak self] in self?.complete() }
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

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
