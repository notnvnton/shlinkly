//
//  ShareSheet.swift
//  Shlinkly
//

#if os(iOS)
import SwiftUI
import UIKit

/// Wraps a URL so `.sheet(item:)` can present a system share sheet for it.
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A SwiftUI bridge to `UIActivityViewController` — the system share sheet.
/// `ShareLink` is the idiomatic way to share, but it's ignored inside a
/// `.swipeActions` button (those must be plain `Button`s). So the swipe Share
/// flips a `@State` and this presents the sheet from that state instead.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
