//
//  TagChip.swift
//  Shlinkly
//

import SwiftUI

/// A single tag chip, the shared style for tags across the app.
///
/// Two sizes: ``Size/regular`` is the Lavender & Matte chip (a 26 pt
/// ``Palette/accentSoft`` capsule) used on the detail screen; ``Size/compact``
/// is the small muted chip the list rows still use, so they keep their height
/// until the list is restyled.
///
/// Pass an `action` to make the chip tappable (it renders as a `Button` with a
/// plain style and a capsule-tight hit area, so it can sit inside a row without
/// hijacking the row's own navigation tap). Omit it for a static chip, e.g. the
/// non-interactive "+N" overflow indicator.
struct TagChip: View {
    enum Size {
        /// The small muted chip of the list rows.
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
                .background(Color.secondary.opacity(0.14), in: Capsule())
                .foregroundStyle(.secondary)
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
