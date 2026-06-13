//
//  DeleteConfirmation.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

extension View {
    /// Presents a centered destructive delete confirmation for the bound short
    /// URL, invoking `onConfirm` only when the user taps Delete. Uses a plain
    /// `.alert` on both platforms — deliberately NOT a row-anchored
    /// `confirmationDialog`/`popover`, whose arrow could point at the wrong row
    /// and invite deleting the wrong link. Binding the item to `nil` (Cancel, or
    /// after confirming) dismisses it.
    ///
    /// Drive it from one `pendingDelete` state held at a stable level (the list
    /// screen root and the detail screen), never per-row.
    func shortURLDeleteConfirmation(
        item: Binding<ShortURL?>,
        onConfirm: @escaping (ShortURL) -> Void
    ) -> some View {
        modifier(ShortURLDeleteConfirmation(item: item, onConfirm: onConfirm))
    }

    /// Presents a centered confirmation for deleting `count` links at once.
    /// Mirrors ``shortURLDeleteConfirmation(item:onConfirm:)`` but for the
    /// multi-select batch — one alert for the whole set.
    func shortURLGroupDeleteConfirmation(
        count: Int,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ShortURLGroupDeleteConfirmation(count: count, isPresented: isPresented, onConfirm: onConfirm))
    }
}

private struct ShortURLDeleteConfirmation: ViewModifier {
    @Binding var item: ShortURL?
    let onConfirm: (ShortURL) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { item != nil }, set: { if !$0 { item = nil } })
    }

    func body(content: Content) -> some View {
        content.alert(
            "Delete this link?",
            isPresented: isPresented,
            presenting: item
        ) { url in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onConfirm(url) }
        } message: { url in
            Text(Self.message(for: url))
        }
    }

    /// "{title} (go.ahodge.de/{shortCode}) and all its analytics will be
    /// permanently deleted. This can't be undone." — the title is dropped when
    /// empty, leaving just the short URL. The host comes from the link's own
    /// `shortUrl` (scheme stripped), so it's never hardcoded.
    private static func message(for url: ShortURL) -> String {
        let display = url.shortUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let target: String
        if let title = url.title, !title.isEmpty {
            target = "\(title) (\(display))"
        } else {
            target = display
        }
        return "\(target) and all its analytics will be permanently deleted. This can't be undone."
    }
}

/// The batch counterpart: one alert covering several selected links.
private struct ShortURLGroupDeleteConfirmation: ViewModifier {
    let count: Int
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Delete \(count) links?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onConfirm() }
        } message: {
            Text("All their analytics will be permanently deleted. This can't be undone.")
        }
    }
}
