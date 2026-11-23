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

// Shlinkly 3.0, "Holds style": every token of the approved layout v3
// (`theme.css`, `.root` light and `.root.dark` dark), with the exact values.
//
// Colors that are opaque in both appearances are asset-catalog colorsets (each
// with a dark appearance). Translucent layers and gradients are constants here.
// The widget and the share extensions are separate targets: they carry a
// minimal copy of the tokens they need (`WidgetTheme.swift`, `ShareTheme` in
// `ShareCreateView.swift`), kept in step with this file.
//
// Brand is ``Palette/brand`` (the `Brand` colorset, `--brand-text`), applied as
// the tint at every scene and sheet root with ``SwiftUICore/View/brandTint()``.
// It is never `Color.accentColor`: macOS honours the `AccentColor` asset only
// when the system accent is "Multicolor".

enum Palette {
    // MARK: Colorsets (opaque in light and dark)

    /// `--brand-text`: links, icons, the tint.
    static let brand = Color("Brand")
    /// `--text`, also `--btn2-text`.
    static let text = Color("Text")
    /// `--text2`.
    static let text2 = Color("Text2")
    /// `--on-brand`: text on ``brandFill``.
    static let onBrand = Color("OnBrand")
    /// `--pastel-text`.
    static let pastelText = Color("PastelText")
    /// `--npastel-text`.
    static let npastelText = Color("NPastelText")
    /// `--seg-text`: unselected segment labels.
    static let segText = Color("SegText")
    /// `--chip-on-text`.
    static let chipOnText = Color("ChipOnText")
    /// `--switch-on`.
    static let switchOn = Color("SwitchOn")
    /// `--danger`.
    static let danger = Color("Danger")
    /// `--ok`: the status dot.
    static let ok = Color("Ok")
    /// `--sel-text`: text on a selected `.mrow`.
    static let selText = Color("SelText")
    /// `--bg-solid`.
    static let bgSolid = Color("BgSolid")
    /// `.sheet` background (`#F7F6F9` light, `--bg-solid` dark).
    static let sheetBg = Color("SheetBg")
    /// `.callout` background (`--card` light, `#2B2A33` dark).
    static let calloutBg = Color("CalloutBg")
    /// `--tint-text`: the label of a `.mbtn-tint` (same values as
    /// `--pastel-text`, kept as its own token).
    static let tintText = Color("TintText")

    // MARK: Translucent layers

    /// `--card`.
    static let card = Color(light: hex(0xFFFFFF), dark: rgba(255, 255, 255, 0.055))
    /// `--card-border`.
    static let cardBorder = Color(light: hex(0xE4E4EA), dark: rgba(255, 255, 255, 0.06))
    /// `--sep`.
    static let sep = Color(light: hex(0xECECF1), dark: rgba(255, 255, 255, 0.07))
    /// `--npastel`.
    static let npastel = Color(light: hex(0xEEEDF2), dark: rgba(255, 255, 255, 0.06))
    /// `--seg-track`.
    static let segTrack = Color(light: hex(0xE7E7ED), dark: rgba(255, 255, 255, 0.06))
    /// `--seg-thumb`.
    static let segThumb = Color(light: hex(0xFFFFFF), dark: rgba(255, 255, 255, 0.14))
    /// `--btn2-border`.
    static let btn2Border = Color(light: rgba(22, 21, 28, 0.06), dark: rgba(255, 255, 255, 0.06))
    /// `--mbtn-border`.
    static let mbtnBorder = Color(light: hex(0xD9D9E1), dark: rgba(255, 255, 255, 0.06))
    /// `--switch-off` (the system draws a switch's off state; kept for reference).
    static let switchOff = Color(light: hex(0xE3E3E9), dark: rgba(255, 255, 255, 0.14))
    /// `--bar-bots`: the bots part of a chart column, the "Unknown" rank bar.
    static let barBots = Color(light: rgba(119, 112, 194, 0.22), dark: rgba(163, 157, 226, 0.22))
    /// `--track`: the rank bars' track.
    static let track = Color(light: hex(0xEFEEF4), dark: rgba(255, 255, 255, 0.07))
    /// `--win`: the Mac window's wash over the behind-window blur.
    static let win = Color(light: rgba(244, 242, 247, 0.84), dark: rgba(34, 33, 41, 0.86))
    /// `--sidebar`: the floating sidebar panel below macOS 26.
    static let sidebar = Color(light: rgba(255, 255, 255, 0.46), dark: rgba(255, 255, 255, 0.05))
    /// `--sidebar-edge`.
    static let sidebarEdge = Color(light: rgba(255, 255, 255, 0.70), dark: rgba(255, 255, 255, 0.08))
    /// `--mcard`.
    static let mcard = Color(light: rgba(255, 255, 255, 0.78), dark: rgba(255, 255, 255, 0.05))
    /// `--mcard-border`.
    static let mcardBorder = Color(light: rgba(22, 21, 28, 0.07), dark: rgba(255, 255, 255, 0.06))
    /// `--tint-border`: the 1 pt inner ring of a `.mbtn-tint`.
    static let tintBorder = Color(light: rgba(67, 60, 140, 0.12), dark: rgba(255, 255, 255, 0.07))
    /// `--sel`: a selected `.mrow`.
    static let sel = Color(light: hex(0xE3E0F5), dark: rgba(169, 163, 230, 0.18))

    // MARK: Gradients (top to bottom)

    /// `--bg`: flat `#F5F5F8` in light; `#25232E` → `#18171D` (42%) → `#111014`
    /// in dark.
    static let bg = LinearGradient(
        stops: [
            .init(color: Color(light: hex(0xF5F5F8), dark: hex(0x25232E)), location: 0),
            .init(color: Color(light: hex(0xF5F5F8), dark: hex(0x18171D)), location: 0.42),
            .init(color: Color(light: hex(0xF5F5F8), dark: hex(0x111014)), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )
    /// `--brand-fill`.
    static let brandFill = vertical(light: (hex(0x554D9F), hex(0x433C8C)), dark: (hex(0x575282), hex(0x423E62)))
    /// `--pastel`: flat `#E6E4F5` in light, `#3D3A5C` → `#312F48` in dark.
    static let pastel = vertical(light: (hex(0xE6E4F5), hex(0xE6E4F5)), dark: (hex(0x3D3A5C), hex(0x312F48)))
    /// `--btn2-bg`.
    static let btn2Fill = vertical(light: (hex(0xEFEEF3), hex(0xE5E4EB)),
                                   dark: (rgba(255, 255, 255, 0.10), rgba(255, 255, 255, 0.07)))
    /// `--tint-bg`: the matte violet of a `.mbtn-tint`.
    static let tintFill = vertical(light: (hex(0xECEAF8), hex(0xE0DDF3)), dark: (hex(0x45416A), hex(0x363352)))
    /// `--mbtn-bg`.
    static let mbtnFill = vertical(light: (hex(0xFFFFFF), hex(0xF4F3F7)),
                                   dark: (rgba(255, 255, 255, 0.11), rgba(255, 255, 255, 0.08)))
    /// `--chip-on-bg`: flat `#16151C` in light, the brand gradient in dark.
    static let chipOnFill = vertical(light: (hex(0x16151C), hex(0x16151C)), dark: (hex(0x575282), hex(0x423E62)))
    /// `--bar`, top color.
    static let barTop = Color(light: hex(0x9B95D8), dark: hex(0xA39DE2))
    /// `--bar`, bottom color.
    static let barBottom = Color(light: hex(0x7770C2), dark: hex(0x7C76C4))
    /// `--bar`.
    static let bar = LinearGradient(colors: [barTop, barBottom], startPoint: .top, endPoint: .bottom)

    // MARK: Shadows

    /// `--btn-shadow`, the inset part: a 1 pt top highlight.
    static let btnHighlight = Color(light: rgba(255, 255, 255, 0.16), dark: rgba(255, 255, 255, 0.08))
    /// `--btn-shadow`, the drop part: `0 1 2`.
    static let btnDrop = Color(light: rgba(40, 30, 90, 0.16), dark: rgba(0, 0, 0, 0.30))
    /// `--btn2-shadow`, the inset top highlight.
    static let btn2Highlight = Color(light: rgba(255, 255, 255, 0.70), dark: rgba(255, 255, 255, 0.06))
    /// `--btn2-shadow`, the inset 1 pt ring.
    static let btn2Ring = Color(light: rgba(22, 21, 28, 0.06), dark: rgba(255, 255, 255, 0.05))

    private static func vertical(light: (RGBA, RGBA), dark: (RGBA, RGBA)) -> LinearGradient {
        LinearGradient(colors: [Color(light: light.0, dark: dark.0), Color(light: light.1, dark: dark.1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Screen background

extension View {
    /// The iPhone screen background, `--bg`, under the safe areas. On macOS the
    /// window's translucent backdrop (``WindowBackdrop``) is the background, so
    /// this adds nothing there.
    @ViewBuilder
    func canvasBackground() -> some View {
        #if os(macOS)
        self
        #else
        background { Palette.bg.ignoresSafeArea() }
        #endif
    }

    /// Tints the view's controls with the brand color. Applied at the root of
    /// every scene and of every sheet and popover (a sheet doesn't always
    /// inherit the tint on macOS).
    func brandTint() -> some View {
        tint(Palette.brand)
    }
}

// MARK: - Color helpers

/// An sRGB color as 0–255 channels and a 0–1 alpha, the way `theme.css` writes
/// them (`rgba(244,242,247,0.84)`).
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
