//
//  Theme.swift
//  Shlinkly
//

import SwiftUI

// The "Lavender & Matte" design tokens: spacing, corner radii and colors, in
// one place. Colors come from the asset catalog (each with a dark appearance);
// the few values the catalog can't hold (the dark gradients) live here.
//
// Typography uses semantic text styles only, so Dynamic Type keeps working:
// headings `.semibold`, everything else `.regular` or `.medium`, numbers
// `.monospacedDigit()`. No `.bold`.

// MARK: - Spacing

/// Spacing scale, in points. Comments give the iOS / macOS values.
enum Space {
    /// 4 / 4
    static let hairline: CGFloat = 4
    /// 8 / 8
    static let tight: CGFloat = 8
    /// 12 / 12. A card's group label has this much room above and below.
    static let labelBand: CGFloat = 12
    /// 14 / 14. Footnote band.
    static let footBand: CGFloat = 14
    /// 16 / 16. Text inset from a card's edge.
    static let cardInset: CGFloat = 16

    #if os(macOS)
    /// 20 / 28. Content inset from the screen's sides.
    static let screenEdge: CGFloat = 28
    /// 24 / 20. Gap between cards.
    static let blockGap: CGFloat = 20
    /// 52 / 40. One-line row.
    static let row: CGFloat = 40
    /// 64 / 52. Two-line row.
    static let rowTwo: CGFloat = 52
    #else
    /// 20 / 28. Content inset from the screen's sides.
    static let screenEdge: CGFloat = 20
    /// 24 / 20. Gap between cards.
    static let blockGap: CGFloat = 24
    /// 52 / 40. One-line row.
    static let row: CGFloat = 52
    /// 64 / 52. Two-line row.
    static let rowTwo: CGFloat = 64
    #endif
}

// MARK: - Corner radii

/// Corner radii, in points (continuous corners). Chips are a `Capsule`.
enum Radius {
    #if os(macOS)
    /// 16 / 14
    static let card: CGFloat = 14
    /// 12 / 10
    static let tile: CGFloat = 10
    /// 10 / 7
    static let control: CGFloat = 7
    #else
    /// 16 / 14
    static let card: CGFloat = 16
    /// 12 / 10
    static let tile: CGFloat = 12
    /// 10 / 7
    static let control: CGFloat = 10
    #endif
}

// MARK: - Colors

/// Named colors from the asset catalog. Every one adapts to light and dark.
enum Palette {
    /// Icons, links, system tint. The app's global accent (`AccentColor`).
    static let accent = Color.accentColor
    /// Screen background (the flat fallback; see ``ThemedCanvas``).
    static let canvas = Color("Canvas")
    /// Cards, the chart callout.
    static let surface = Color("Surface")
    /// Tiles inside cards, bar tracks.
    static let sunken = Color("Sunken")
    /// The 1 pt card outline.
    static let cardBorder = Color("CardBorder")
    /// Separators inside cards, chart grid lines.
    static let hairline = Color("Hairline")
    /// Primary text.
    static let textPrimary = Color("TextPrimary")
    /// Secondary text, group labels.
    static let textSecondary = Color("TextSecondary")
    /// Text on ``accentSoft``, the short URL.
    static let accentText = Color("AccentText")
    /// Chips, tiles' pastel fill.
    static let accentSoft = Color("AccentSoft")
    /// Primary button fill (dark mode draws ``Gradients/buttonFillDark``).
    static let buttonFill = Color("ButtonFill")
    /// Chart and breakdown bars.
    static let seriesPeople = Color("SeriesPeople")
    /// The bots segment, "Unknown" bars.
    static let seriesBots = Color("SeriesBots")

    /// Dark-mode-only gradients. Light mode has no gradients anywhere.
    enum Gradients {
        /// The dark canvas: `#1E1D26` at the top fading to `#141318` at 55%
        /// of the height, flat below.
        static let canvasDark = LinearGradient(
            stops: [
                .init(color: Color(red: 0x1E / 255, green: 0x1D / 255, blue: 0x26 / 255), location: 0),
                .init(color: Color(red: 0x14 / 255, green: 0x13 / 255, blue: 0x18 / 255), location: 0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// The dark primary button: `#5A5486` to `#47426B`, top to bottom.
        static let buttonFillDark = LinearGradient(
            colors: [
                Color(red: 0x5A / 255, green: 0x54 / 255, blue: 0x86 / 255),
                Color(red: 0x47 / 255, green: 0x42 / 255, blue: 0x6B / 255),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Canvas

/// The screen background: the flat ``Palette/canvas`` in light mode, the soft
/// vertical fade in dark mode. Extends under the safe areas.
struct ThemedCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                Palette.Gradients.canvasDark
            } else {
                Palette.canvas
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Puts the themed screen background (``ThemedCanvas``) behind the view.
    func canvasBackground() -> some View {
        background { ThemedCanvas() }
    }
}
