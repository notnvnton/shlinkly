//
//  TagChip.swift
//  Shlinkly
//

import SwiftUI

/// A single tag chip, the shared style for tags across the app.
///
/// Both sizes are ``Palette/accentSoft`` capsules with ``Palette/accentText``
/// labels. ``Size/regular`` (26 pt) is the detail screen's; ``Size/compact`` is
/// the small chip of the list rows, sized so it doesn't inflate row height.
///
/// Pass an `action` to make the chip tappable (it renders as a `Button` with a
/// plain style and a capsule-tight hit area, so it can sit inside a row without
/// hijacking the row's own navigation tap). Omit it for a static chip, e.g. the
/// non-interactive "+N" overflow indicator.
struct TagChip: View {
    enum Size {
        /// The small chip of the list rows.
        case compact
        /// The detail screen's chip: 26 pt tall, accent-tinted.
        case regular
    }

    let text: String
    var size: Size = .compact
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        switch size {
        case .compact:
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.accentSoft, in: Capsule())
                .foregroundStyle(Palette.accentText)
                // Confine the hit area to the visible capsule so taps don't
                // bleed into the surrounding row.
                .contentShape(Capsule())
        case .regular:
            Text(text)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .background(Palette.accentSoft, in: Capsule())
                .foregroundStyle(Palette.accentText)
                .contentShape(Capsule())
        }
    }
}
