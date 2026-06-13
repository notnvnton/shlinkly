//
//  CopyButton.swift
//  Shlinkly
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A copy-to-clipboard button with brief visual confirmation: the icon swaps
/// from `doc.on.doc` to a green `checkmark` for ~1.2s (with a light haptic on
/// iOS), then swaps back. Shared by the detail header and the edit form's
/// read-only short-code field so the feedback is identical in both places.
struct CopyButton: View {
    /// The string copied to the pasteboard on tap.
    let value: String
    /// Describes what gets copied; used for the macOS tooltip and the
    /// accessibility label (which becomes "Copied" briefly after a tap).
    var label: String = "Copy"

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            copy()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.subheadline)
                .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                // Fixed box so the doc → checkmark swap can't nudge layout.
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(didCopy ? "Copied" : label)
    }

    private func copy() {
        Clipboard.copy(value)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
        }
    }
}
