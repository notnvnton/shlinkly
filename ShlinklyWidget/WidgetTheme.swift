//
//  WidgetTheme.swift
//  ShlinklyWidget
//

import SwiftUI
import UIKit

/// The layout v3 tokens the widget uses (`Widgets.html`). The widget is a
/// separate target that doesn't build `Shlinkly/Design/Theme.swift`, so this is
/// a minimal copy with the same values: it mirrors `Palette` there
/// (`theme.css`); change both together.
enum WidgetTheme {
    /// The widget's background: `#FFFFFF` light, `#1F1E25` dark.
    static let background = adaptive(light: (0xFF, 0xFF, 0xFF, 1), dark: (0x1F, 0x1E, 0x25, 1))
    /// `--brand-text`.
    static let brand = adaptive(light: (0x43, 0x3C, 0x8C, 1), dark: (0xA9, 0xA3, 0xE6, 1))
    /// `--text`.
    static let text = adaptive(light: (0x16, 0x15, 0x1C, 1), dark: (0xED, 0xEC, 0xF2, 1))
    /// `--on-brand`.
    static let onBrand = adaptive(light: (0xFF, 0xFF, 0xFF, 1), dark: (0xEE, 0xED, 0xF5, 1))
    /// `--pastel-text`.
    static let pastelText = adaptive(light: (0x32, 0x2C, 0x78, 1), dark: (0xDC, 0xD9, 0xF7, 1))
    /// `--brand-fill`.
    static let brandFill = LinearGradient(colors: [
        adaptive(light: (0x55, 0x4D, 0x9F, 1), dark: (0x57, 0x52, 0x82, 1)),
        adaptive(light: (0x43, 0x3C, 0x8C, 1), dark: (0x42, 0x3E, 0x62, 1)),
    ], startPoint: .top, endPoint: .bottom)
    /// `--pastel`.
    static let pastel = LinearGradient(colors: [
        adaptive(light: (0xE6, 0xE4, 0xF5, 1), dark: (0x3D, 0x3A, 0x5C, 1)),
        adaptive(light: (0xE6, 0xE4, 0xF5, 1), dark: (0x31, 0x2F, 0x48, 1)),
    ], startPoint: .top, endPoint: .bottom)

    typealias Channels = (Double, Double, Double, Double)

    private static func adaptive(light: Channels, dark: Channels) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
    }
}

/// The Shlinkly mark (mirrors `BrandMark` in the app): two chevrons on a
/// `#3E309C` → `#6456DD` tile.
struct WidgetBrandMark: View {
    var side: CGFloat = 32
    var radius: CGFloat = 9
    var glyph: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0x3E / 255, green: 0x30 / 255, blue: 0x9C / 255),
                                          Color(red: 0x64 / 255, green: 0x56 / 255, blue: 0xDD / 255)],
                                 startPoint: UnitPoint(x: 0.329, y: 0.030),
                                 endPoint: UnitPoint(x: 0.671, y: 0.970)))
            .frame(width: side, height: side)
            .overlay {
                Canvas { context, size in
                    let unit = size.width / 34
                    func chevron(from x: CGFloat) -> Path {
                        var path = Path()
                        path.move(to: CGPoint(x: x * unit, y: 10 * unit))
                        path.addLine(to: CGPoint(x: (x + 10) * unit, y: 10 * unit))
                        path.addLine(to: CGPoint(x: (x + 4) * unit, y: 24 * unit))
                        return path
                    }
                    let style = StrokeStyle(lineWidth: 5 * unit, lineCap: .round, lineJoin: .round)
                    context.stroke(chevron(from: 6),
                                   with: .color(Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xEA / 255)),
                                   style: style)
                    context.stroke(chevron(from: 17),
                                   with: .color(Color(red: 0xCF / 255, green: 0xCF / 255, blue: 0xD8 / 255)),
                                   style: style)
                }
                .frame(width: glyph, height: glyph)
            }
            .accessibilityHidden(true)
    }
}
