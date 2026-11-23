//
//  ActionTile.swift
//  Shlinkly
//

import SwiftUI

/// The face of an action tile: an SF Symbol over a short label on a
/// ``Palette/sunken`` tile (iOS) or a matte button face (macOS). It stretches
/// to share its row equally with its neighbours (lay them out in an `HStack`
/// with ``Space/tight`` spacing).
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
        .frame(maxWidth: .infinity, minHeight: max(Self.height, 44))
        #if os(iOS)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        #endif
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// The tiles' button style. iOS: the flat tile dims while pressed (no
/// highlight, gloss or shadow). macOS: the convex ``MatteButtonStyle`` face at
/// the tile's height and radius.
struct ActionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        MatteButtonStyle(minHeight: 52, cornerRadius: Radius.tile)
            .makeBody(configuration: configuration)
        #else
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
        #endif
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
