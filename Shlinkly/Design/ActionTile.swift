//
//  ActionTile.swift
//  Shlinkly
//

#if os(iOS)
import SwiftUI

/// The face of an action tile: an SF Symbol over a short label on a
/// ``Palette/sunken`` tile. It stretches to share its row equally with its
/// neighbours (lay them out in an `HStack` with ``Space/tight`` spacing).
/// iPhone only: the Mac header uses native push buttons instead.
///
/// The symbol sits in a fixed 24×24 box, so every tile's label shares one
/// baseline whatever the symbol's own height.
///
/// Kept apart from the button so the same tile can be the label of a plain
/// ``ActionTile`` or of a `ShareLink`; style either with
/// ``ActionTileButtonStyle``.
struct ActionTileLabel: View {
    let title: String
    let systemImage: String

    /// 64 pt. A minimum, so large text can grow it.
    private static let height: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(Palette.accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: Self.height)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// The tiles' button style: the flat tile dims while pressed. No highlight,
/// gloss or shadow.
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
#endif
