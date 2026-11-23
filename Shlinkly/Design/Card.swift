//
//  Card.swift
//  Shlinkly
//

import SwiftUI

/// A matte card: content on ``Palette/surface`` in a continuous rounded
/// rectangle with a 1 pt ``Palette/cardBorder`` outline and no shadow. On
/// macOS it is translucent instead: a soft vertical gradient over the window's
/// wash, a 0.5 pt edge and, in light mode, a faint shadow.
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
                    CardLabel(label)
                    Spacer(minLength: Space.tight)
                    accessory
                }
                .padding(.horizontal, Space.cardInset)
                .padding(.vertical, Space.labelBand)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .background {
            shape
                .fill(Palette.Mac.cardFill)
                .shadow(color: Palette.Mac.cardShadow, radius: 2, y: 1)
        }
        .overlay(shape.strokeBorder(Palette.Mac.cardBorder, lineWidth: 0.5))
        #else
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.cardBorder, lineWidth: 1))
        #endif
    }
}

/// A card's group label: `.footnote.weight(.medium)` in
/// ``Palette/textSecondary``, marked as a header. For cards that lay out their
/// own label band (the chart card).
struct CardLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
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
