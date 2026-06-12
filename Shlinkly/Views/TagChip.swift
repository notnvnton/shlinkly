//
//  TagChip.swift
//  Shlinkly
//

import SwiftUI

/// A single compact tag chip: small, tight, muted. The shared style for tags
/// across the app — used on the detail screen and in the list rows.
///
/// Pass an `action` to make the chip tappable (it renders as a `Button` with a
/// plain style and a capsule-tight hit area, so it can sit inside a row without
/// hijacking the row's own navigation tap). Omit it for a static chip, e.g. the
/// non-interactive "+N" overflow indicator.
struct TagChip: View {
    let text: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(.secondary)
            // Confine the hit area to the visible capsule so taps don't bleed
            // into the surrounding row.
            .contentShape(Capsule())
    }
}
