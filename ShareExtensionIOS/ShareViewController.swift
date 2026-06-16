//
//  ShareViewController.swift
//  ShareExtensionIOS
//

import UIKit
import SwiftUI

/// Thin host: pulls the shared URL out of the extension context, then hosts the
/// shared ``ShareCreateView`` (which does the resolve + create) in a child
/// hosting controller pinned to the edges. `onDone` completes the request.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let longURL = await ShareItemReader.extractURL(from: extensionContext)
            present(longURL: longURL)
        }
    }

    @MainActor
    private func present(longURL: String?) {
        // No URL in the share → nothing to do; close cleanly rather than crash.
        guard let longURL else { complete(); return }

        let host = UIHostingController(
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
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
