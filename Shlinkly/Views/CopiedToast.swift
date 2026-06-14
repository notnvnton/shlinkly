//
//  CopiedToast.swift
//  Shlinkly
//

import SwiftUI

/// A small floating "Copied" confirmation pill. There's no native toast, so this
/// is hand-rolled: the host view fades it in, keeps it ~1.5s, then fades it out
/// (see ``View/copiedToast(isPresented:)``). Shared by the list's copy actions
/// across the swipe, the context menu and the macOS hover button.
struct CopiedToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied")
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityLabel("Copied to clipboard")
    }
}

extension View {
    /// Overlays a transient "Copied" toast near the bottom edge while
    /// `isPresented` is true. The caller flips `isPresented` (with animation) and
    /// schedules flipping it back; this just renders the fade.
    func copiedToast(isPresented: Bool) -> some View {
        overlay(alignment: .bottom) {
            if isPresented {
                CopiedToast()
                    .padding(.bottom, 28)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }
}
