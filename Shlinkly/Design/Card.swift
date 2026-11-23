//
//  Card.swift
//  Shlinkly
//

import SwiftUI

/// A matte card: content on ``Palette/surface`` in a continuous rounded
/// rectangle with a 1 pt ``Palette/cardBorder`` outline and no shadow.
///
/// The card has no vertical padding of its own. It is built from bands and
/// rows, each of which insets its text by ``Space/cardInset`` so every line in
/// the card shares one leading edge. An optional label band sits on top: the
/// group label with ``Space/labelBand`` above and below, and an optional
/// trailing accessory in the same band.
struct Card<Content: View, Accessory: View>: View {
    private let label: String?
    private let accessory: Accessory
    private let content: Content

    init(
        _ label: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                HStack(alignment: .center, spacing: Space.tight) {
                    Text(label)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.tight)
                    accessory
                }
                .padding(.horizontal, Space.cardInset)
                .padding(.vertical, Space.labelBand)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.cardBorder, lineWidth: 1))
    }
}

extension Card where Accessory == EmptyView {
    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(label, content: content, accessory: { EmptyView() })
    }
}

/// A 0.5 pt ``Palette/hairline`` separator between a card's rows, inset on the
/// leading side to the card's text edge.
struct CardHairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, Space.cardInset)
            .accessibilityHidden(true)
    }
}
