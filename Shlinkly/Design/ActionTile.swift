//
//  ActionTile.swift
//  Shlinkly
//

import SwiftUI

/// The face of an action tile: an SF Symbol over a short label on a
/// ``Palette/sunken`` tile. It stretches to share its row equally with its
/// neighbours (lay them out in an `HStack` with ``Space/tight`` spacing).
///
/// Kept apart from the button so the same tile can be the label of a plain
/// ``ActionTile`` or of a `ShareLink`; style either with
/// ``ActionTileButtonStyle``.
struct ActionTileLabel: View {
    let title: String
    let systemImage: String

    /// The symbol's 22 pt, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    /// 64 pt on iOS, 52 pt on macOS. A minimum, so large text can grow it.
    private static var height: CGFloat {
        #if os(macOS)
        52
        #else
        64
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.accent)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: max(Self.height, 44))
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// Dims a tile while it is pressed. No highlight, gloss or shadow.
struct ActionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A tappable ``ActionTileLabel``.
struct ActionTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ActionTileLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(ActionTileButtonStyle())
        .help(title)
    }
}
