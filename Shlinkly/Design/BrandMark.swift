//
//  BrandMark.swift
//  Shlinkly
//

import SwiftUI

/// The Shlinkly mark as layout v3 draws it (onboarding, widgets): two chevrons
/// on a `#3E309C` → `#6456DD` tile (CSS `linear-gradient(160deg, …)`).
/// `side` is the tile, `radius` its corner; the glyph is `glyph` points.
struct BrandMark: View {
    var side: CGFloat = 56
    var radius: CGFloat = 14
    var glyph: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex(0x3E309C)), Color(hex(0x6456DD))],
                                 startPoint: UnitPoint(x: 0.329, y: 0.030),
                                 endPoint: UnitPoint(x: 0.671, y: 0.970)))
            .frame(width: side, height: side)
            .overlay { BrandGlyph().frame(width: glyph, height: glyph) }
            .accessibilityHidden(true)
    }
}

/// The two chevrons of the SVG (`viewBox="0 0 34 34"`): `M6 10h10l-6 14` in
/// `#E4E4EA` and `M17 10h10l-6 14` in `#CFCFD8`, 5 wide, round caps and joins.
private struct BrandGlyph: View {
    var body: some View {
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
            context.stroke(chevron(from: 6), with: .color(Color(hex(0xE4E4EA))), style: style)
            context.stroke(chevron(from: 17), with: .color(Color(hex(0xCFCFD8))), style: style)
        }
    }
}
