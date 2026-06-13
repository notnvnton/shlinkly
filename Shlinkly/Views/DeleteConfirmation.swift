//
//  DeleteConfirmation.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

extension View {
    /// Presents a destructive delete confirmation for the bound short URL,
    /// invoking `onConfirm` when the user confirms. Uses a `confirmationDialog`
    /// on iOS and a destructive alert on macOS, matching each platform's idiom.
    /// Binding the presented item to `nil` (Cancel, or after confirming)
    /// dismisses it.
    func shortURLDeleteConfirmation(
        item: Binding<ShortURL?>,
        onConfirm: @escaping (ShortURL) -> Void
    ) -> some View {
        modifier(ShortURLDeleteConfirmation(item: item, onConfirm: onConfirm))
    }
}

private struct ShortURLDeleteConfirmation: ViewModifier {
    @Binding var item: ShortURL?
    let onConfirm: (ShortURL) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { item != nil }, set: { if !$0 { item = nil } })
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.confirmationDialog(
            "Delete this link?",
            isPresented: isPresented,
            titleVisibility: .visible,
            presenting: item
        ) { url in
            Button("Delete", role: .destructive) { onConfirm(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("\(url.shortUrl) will be permanently deleted.")
        }
        #else
        content.alert(
            "Delete this link?",
            isPresented: isPresented,
            presenting: item
        ) { url in
            Button("Delete", role: .destructive) { onConfirm(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("\(url.shortUrl) will be permanently deleted.")
        }
        #endif
    }
}
