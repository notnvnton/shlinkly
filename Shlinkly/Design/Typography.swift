//
//  Typography.swift
//  Shlinkly
//

import SwiftUI

/// The layout's exact type: the system font at the point size and weight the
/// artboard gives (CSS px map 1:1 to points), scaled with Dynamic Type through
/// `@ScaledMetric` relative to the nearest text style. Weights: 600 →
/// `.semibold`, 500 → `.medium`, 400 → `.regular`. Never bold.
private struct LayoutFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, tracking: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(nearest: size))
        self.weight = weight
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
    }

    /// The text style whose default size is nearest to `size` (iOS sizes:
    /// caption2 11, caption 12, footnote 13, subheadline 15, callout 16,
    /// body 17, title3 20, title2 22, title 28, largeTitle 34).
    private static func textStyle(nearest size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
    }
}

extension View {
    /// The layout font: `size` points at `weight`, scaled with Dynamic Type.
    /// `tracking` is the CSS `letter-spacing` (the large titles use it).
    func layoutFont(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        modifier(LayoutFont(size: size, weight: weight, tracking: tracking))
    }
}
