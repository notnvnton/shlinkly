//
//  Theme.swift
//  Shlinkly
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The "Lavender & Matte" design tokens: spacing, corner radii and colors, in
// one place. Colors come from the asset catalog (each with a dark appearance);
// the values the catalog can't hold (gradients, and the macOS translucent
// surfaces, which differ from iOS) live here.
//
// The brand color is ``Palette/accent``, read from the `Brand` colorset. It is
// never `Color.accentColor`: on macOS SwiftUI honours the `AccentColor` asset
// only when the user picks "Multicolor" as the system accent, so anything that
// reads it turns system blue on most Macs. Scene and sheet roots apply it as
// the tint with ``SwiftUICore/View/brandTint()``.
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
    /// Icons, links, the tint. The `Brand` colorset (same values as
    /// `AccentColor`, which only iOS system controls still read).
    static let accent = Color("Brand")
    /// Screen background (the flat fallback; see ``ThemedCanvas``).
    static let canvas = Color("Canvas")
    /// Cards, the chart callout.
    static let surface = Color("Surface")
    /// Tiles inside cards, bar tracks. Translucent on macOS, so the window's
    /// wash shows through.
    #if os(macOS)
    static let sunken = Color(light: rgba(241, 239, 248, 0.9), dark: rgba(255, 255, 255, 0.05))
    #else
    static let sunken = Color("Sunken")
    #endif

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
    /// The dimmed "Unknown" bars of the ranked breakdowns.
    static let seriesBots = Color("SeriesBots")

    /// The visits chart's columns: people as a soft brand gradient, top to
    /// bottom; bots as the same hue, translucent, above them — the empty part
    /// of a glass tube filled to the people level.
    enum Bars {
        static let peopleTop = Color(light: hex(0x7A72CC), dark: hex(0xC4BEF0))
        static let peopleBottom = Color(light: hex(0x5249A8), dark: hex(0x9C94E0))
        static let bots = Color(light: hex(0x5249A8, alpha: 0.22), dark: hex(0xB3ACE6, alpha: 0.24))
    }

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
    /// On macOS it adds nothing: the window's translucent backdrop
    /// (``WindowBackdrop``) is the screen background there.
    @ViewBuilder
    func canvasBackground() -> some View {
        #if os(macOS)
        self
        #else
        background { ThemedCanvas() }
        #endif
    }

    /// Tints the view's controls with the brand color. Applied at the root of
    /// every scene and of every sheet and popover (a sheet doesn't always
    /// inherit the tint on macOS).
    func brandTint() -> some View {
        tint(Palette.accent)
    }
}

// MARK: - macOS surfaces

#if os(macOS)
extension Palette {
    /// The translucent matte window (approved mockup values).
    enum Mac {
        /// The wash over the window's behind-window blur, top-left to
        /// bottom-right: lavender to a soft rose, clearly visible even over a
        /// white window behind. `TextSecondary` on its light start stays above
        /// 5:1 over any backdrop (6.1:1 over white, 5.0:1 over black).
        static let windowWash = LinearGradient(
            stops: [
                .init(color: Color(light: rgba(233, 229, 248, 0.92), dark: rgba(44, 40, 62, 0.88)), location: 0),
                .init(color: Color(light: rgba(240, 234, 246, 0.90), dark: rgba(36, 33, 50, 0.88)), location: 0.55),
                .init(color: Color(light: rgba(246, 236, 240, 0.88), dark: rgba(40, 32, 40, 0.88)), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// The lavender wash over the sidebar material, top to bottom. Only
        /// below macOS 26; from 26 the system's floating glass sidebar shows
        /// through instead.
        static let sidebarWash = LinearGradient(
            colors: [
                Color(light: rgba(232, 229, 243, 0.62), dark: rgba(50, 47, 66, 0.55)),
                Color(light: rgba(237, 232, 241, 0.48), dark: rgba(40, 37, 52, 0.45)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// A card's soft vertical gradient (instead of flat white).
        static let cardFill = LinearGradient(
            colors: [
                Color(light: rgba(255, 255, 255, 0.90), dark: rgba(50, 48, 62, 0.82)),
                Color(light: rgba(252, 251, 254, 0.82), dark: rgba(42, 40, 52, 0.80)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        /// A card's 0.5 pt edge.
        static let cardBorder = Color(light: rgba(0, 0, 0, 0.08), dark: rgba(255, 255, 255, 0.08))
        /// A card's shadow: light mode only.
        static let cardShadow = Color(light: rgba(0, 0, 0, 0.05), dark: rgba(0, 0, 0, 0))

        /// The soft lavender selection pill (list rows, sidebar), top to bottom.
        static let selectionFill = LinearGradient(
            colors: [
                Color(light: rgba(234, 231, 248, 0.98), dark: rgba(179, 172, 230, 0.20)),
                Color(light: rgba(226, 222, 244, 0.98), dark: rgba(179, 172, 230, 0.14)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        /// The selection pill's 0.5 pt edge: the brand color at 18%.
        static let selectionEdge = Palette.accent.opacity(0.18)
    }
}
#endif

// MARK: - Color helpers

/// An sRGB color as 0–255 channels and a 0–1 alpha, the way the mockup
/// specifies them (`rgba(247,245,251,0.84)`).
typealias RGBA = (red: Double, green: Double, blue: Double, alpha: Double)

nonisolated func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> RGBA {
    (red, green, blue, alpha)
}

/// `#RRGGBB` as ``RGBA``.
nonisolated func hex(_ value: UInt32, alpha: Double = 1) -> RGBA {
    (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF), alpha)
}

extension Color {
    /// A fixed sRGB color.
    nonisolated init(_ color: RGBA) {
        self.init(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255,
                  opacity: color.alpha)
    }

    /// A color that follows the appearance: `light` in light mode, `dark` in
    /// dark mode. Resolved by AppKit / UIKit, so it also adapts inside
    /// gradients and shadows.
    nonisolated init(light: RGBA, dark: RGBA) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            let color = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: color.red / 255, green: color.green / 255, blue: color.blue / 255,
                           alpha: color.alpha)
        })
        #else
        self.init(uiColor: UIColor { @Sendable traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red / 255, green: color.green / 255, blue: color.blue / 255,
                           alpha: color.alpha)
        })
        #endif
    }
}
