//
//  Buttons.swift
//  Shlinkly
//

import SwiftUI

// The buttons of layout v3 (`theme.css`), with their states:
// - iPhone `.btn-primary` / `.btn-secondary`: pressed = brightness 0.96, 120 ms.
// - Mac `.mbtn` (every variant: plain, tint, primary, square, danger, ghost):
//   - hover = brightness × `--hover-lift` (light 0.97, a touch deeper; dark
//     1.12, a touch lighter);
//   - pressed = brightness × `--press-dim` (light 0.93, dark 0.88), scale 0.97,
//     the outer shadow off (and, on `.mbtn-primary`, the top highlight off too);
//   - 120 ms into pressed, 160 ms back out and for hover;
//   - disabled = 40% opacity, no reaction.
//
// CSS `filter: brightness(x)` multiplies the colors by x. Below 1 that is
// `colorMultiply`. Above 1 (dark hover) SwiftUI has no multiply, so a copy of
// the face multiplied by x − 1 is added on top (`.plusLighter`): face × x for
// every opaque pixel (``SwiftUICore/View/cssBrightness(_:)``).

/// A 1 pt highlight along the top inside edge of `shape` (the CSS
/// `inset 0 1px 0` shadows).
private struct TopHighlight<S: Shape>: View {
    let shape: S
    let color: Color

    var body: some View {
        shape
            .fill(color)
            .mask(alignment: .top) {
                Rectangle().frame(height: 1)
            }
            .allowsHitTesting(false)
    }
}

/// `.btn-primary` (iPhone): 50 pt, full width, radius 14, `--brand-fill`,
/// 17 pt semibold `--on-brand`, `--btn-shadow`.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return LargeButtonBody(configuration: configuration) {
            configuration.label
                .layoutFont(17, .semibold)
                .foregroundStyle(Palette.onBrand)
        } background: {
            shape
                .fill(Palette.brandFill)
                .overlay { TopHighlight(shape: shape, color: Palette.btnHighlight) }
                .shadow(color: Palette.btnDrop, radius: 1, y: 1)
        }
    }
}

/// `.btn-secondary` (iPhone): 50 pt, full width, radius 14, `--btn2-bg`,
/// 17 pt semibold `--btn2-text`, `--btn2-shadow`.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return LargeButtonBody(configuration: configuration) {
            configuration.label
                .layoutFont(17, .semibold)
                .foregroundStyle(Palette.text)
        } background: {
            shape
                .fill(Palette.btn2Fill)
                .overlay { TopHighlight(shape: shape, color: Palette.btn2Highlight) }
                .overlay { shape.strokeBorder(Palette.btn2Ring, lineWidth: 1) }
        }
    }
}

private struct LargeButtonBody<Label: View, Background: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let label: Label
    @ViewBuilder let background: Background
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background { background }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .colorMultiply(Color(white: configuration.isPressed ? 0.96 : 1))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.btn-text` / `.btn-danger-text` / `.navlink`: a text button, 44 pt tall,
/// in `--brand-text` (or `--danger`).
struct TextButtonStyle: ButtonStyle {
    enum Role {
        case brand
        case danger
    }

    var role: Role = .brand
    /// 16 pt (`.btn-text`), 17 pt (`.navlink`).
    var size: CGFloat = 16
    var weight: Font.Weight = .medium

    func makeBody(configuration: Configuration) -> some View {
        TextButtonBody(configuration: configuration, role: role, size: size, weight: weight)
    }
}

private struct TextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: TextButtonStyle.Role
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .layoutFont(size, weight)
            .foregroundStyle(role == .danger ? Palette.danger : Palette.brand)
            .lineLimit(1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
    }
}

/// `.mbtn` and its variants (Mac): 26 pt, radius 6, text only, 13 pt medium.
/// The plain and tint buttons have a minimum width of 76, so "Copy" → "Copied"
/// never changes their width or moves their neighbours. States: see the top
/// of this file (``MacButtonReaction``).
struct MacButtonStyle: ButtonStyle {
    enum Kind {
        /// `.mbtn`: `--mbtn-bg`, a 1 pt `--mbtn-border` ring, `0 1 1` at 4%.
        case normal
        /// `.mbtn-tint`, the action buttons in content (Copy, Share, Open, QR
        /// code, Copy Image, Edit, Add Server…): matte `--tint-bg`,
        /// `--tint-text`, a 1 pt `--tint-border` ring, `0 1 1` at 4%.
        case tint
        /// `.mbtn-primary`: `--brand-fill`, `--on-brand`, `--btn-shadow`.
        case primary
        /// `.mbtn-danger`, as the sheets draw it: `--danger` text, no fill.
        case danger
        /// The sidebar toggle as `MacMain` draws it: a `.mbtn-sq` with no fill
        /// or shadow, its glyph in `--text2`.
        case ghost
    }

    var kind: Kind = .normal
    /// `.mbtn-sq`: 26 × 26, for a single glyph.
    var square = false
    var height: CGFloat = 26
    var fontSize: CGFloat = 13
    /// `nil` uses the class default: 76 for `.mbtn`, 0 for danger / square.
    var minWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        MacButtonBody(configuration: configuration, kind: kind, square: square, height: height,
                      fontSize: fontSize, minWidth: minWidth)
    }
}

private struct MacButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: MacButtonStyle.Kind
    let square: Bool
    let height: CGFloat
    let fontSize: CGFloat
    let minWidth: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    /// Set by ``MacButtonPair``: the face fills the width it's given.
    @Environment(\.macButtonFillsWidth) private var fillsWidth
    @State private var isHovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        face(pressed: pressed)
            .modifier(MacButtonReaction(pressed: pressed, hovering: isHovering && isEnabled))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
    }

    private func face(pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .layoutFont(fontSize, .medium)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : (kind == .danger ? 4 : 12))
            .frame(width: square ? height : nil, height: height)
            .frame(minWidth: resolvedMinWidth, maxWidth: fillsWidth && !square ? .infinity : nil)
            .background {
                switch kind {
                case .normal:
                    shape
                        .fill(Palette.mbtnFill)
                        .overlay { shape.strokeBorder(Palette.mbtnBorder, lineWidth: 1) }
                        .shadow(color: .black.opacity(pressed ? 0 : 0.04), radius: 0.5, y: 1)
                case .tint:
                    shape
                        .fill(Palette.tintFill)
                        .overlay { shape.strokeBorder(Palette.tintBorder, lineWidth: 1) }
                        .shadow(color: .black.opacity(pressed ? 0 : 0.04), radius: 0.5, y: 1)
                case .primary:
                    shape
                        .fill(Palette.brandFill)
                        .overlay {
                            TopHighlight(shape: shape, color: Palette.btnHighlight)
                                .opacity(pressed ? 0 : 1)
                        }
                        .shadow(color: pressed ? .clear : Palette.btnDrop, radius: 1, y: 1)
                case .danger, .ghost:
                    Color.clear
                }
            }
            .contentShape(shape)
    }

    private var foreground: Color {
        switch kind {
        case .normal: return Palette.text
        case .tint: return Palette.tintText
        case .primary: return Palette.onBrand
        case .danger: return Palette.danger
        case .ghost: return Palette.text2
        }
    }

    private var resolvedMinWidth: CGFloat? {
        if let minWidth { return minWidth }
        if square || kind == .danger || kind == .ghost { return nil }
        return 76
    }
}

/// Every Mac button's hover and pressed reaction (`.mbtn:hover`,
/// `.mbtn:active`): brightness × `--hover-lift` on hover, × `--press-dim` and
/// scale 0.97 while pressed; 120 ms into pressed, 160 ms back out and for
/// hover. The caller passes `false` for both while the button is disabled.
struct MacButtonReaction: ViewModifier {
    let pressed: Bool
    let hovering: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// `--hover-lift`.
    private var hoverLift: Double { colorScheme == .dark ? 1.12 : 0.97 }
    /// `--press-dim`.
    private var pressDim: Double { colorScheme == .dark ? 0.88 : 0.93 }

    func body(content: Content) -> some View {
        let factor = pressed ? pressDim : (hovering ? hoverLift : 1)
        content
            .cssBrightness(factor)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeInOut(duration: pressed ? 0.12 : 0.16), value: pressed)
            .animation(.easeInOut(duration: 0.16), value: hovering)
    }
}

extension View {
    /// CSS `filter: brightness(factor)`: every color channel × `factor`.
    /// Below 1 a `colorMultiply`; above 1 a copy of the view multiplied by
    /// `factor − 1` is added on top (`.plusLighter`), which gives
    /// view × `factor` for every opaque pixel. The copy is always there (black
    /// at 1 and below), so the change animates.
    func cssBrightness(_ factor: Double) -> some View {
        colorMultiply(Color(white: min(factor, 1)))
            .overlay {
                colorMultiply(Color(white: max(factor - 1, 0)))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension EnvironmentValues {
    /// Whether a ``MacButtonStyle`` face fills the width it's given (inside
    /// a ``MacButtonPair``) instead of hugging its label.
    @Entry var macButtonFillsWidth = false
}

#if os(macOS)
/// `.mbtn-pair`: a sheet footer's confirm pair (Cancel + Create link / Save)
/// as one group, every button as wide as the widest, 8 pt apart.
struct MacButtonPair<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        EqualWidthRow(spacing: 8) {
            content
        }
        .environment(\.macButtonFillsWidth, true)
        .fixedSize()
    }
}
#endif

extension ButtonStyle where Self == MacButtonStyle {
    /// `.mbtn`.
    static var mac: MacButtonStyle { MacButtonStyle() }
    /// `.mbtn.mbtn-tint`.
    static var macTint: MacButtonStyle { MacButtonStyle(kind: .tint) }
    /// `.mbtn.mbtn-primary`.
    static var macPrimary: MacButtonStyle { MacButtonStyle(kind: .primary) }
    /// `.mbtn.mbtn-danger` (no fill).
    static var macDanger: MacButtonStyle { MacButtonStyle(kind: .danger) }
    /// `.mbtn.mbtn-sq`.
    static var macSquare: MacButtonStyle { MacButtonStyle(square: true) }
    /// `.mbtn.mbtn-sq.mbtn-primary`.
    static var macSquarePrimary: MacButtonStyle { MacButtonStyle(kind: .primary, square: true) }
    /// The sidebar toggle: `.mbtn-sq` without fill or shadow.
    static var macGhostSquare: MacButtonStyle { MacButtonStyle(kind: .ghost, square: true) }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// `.btn-primary`.
    static var layoutPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    /// `.btn-secondary`.
    static var layoutSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == TextButtonStyle {
    /// `.btn-text`.
    static var layoutText: TextButtonStyle { TextButtonStyle() }
    /// `.btn-danger-text`.
    static var layoutDangerText: TextButtonStyle { TextButtonStyle(role: .danger) }
    /// `.navlink` (17 pt medium); pass `.semibold` for the drawn "Done".
    static func navLink(_ weight: Font.Weight = .medium) -> TextButtonStyle {
        TextButtonStyle(size: 17, weight: weight)
    }
}

/// The `.btn-primary` face on its own, for a `Menu` label (a menu can't take a
/// button style on every platform). Same metrics as ``PrimaryButtonStyle``.
struct PrimaryButtonFace: View {
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Text(title)
            .layoutFont(17, .semibold)
            .foregroundStyle(Palette.onBrand)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                shape
                    .fill(Palette.brandFill)
                    .overlay { TopHighlight(shape: shape, color: Palette.btnHighlight) }
                    .shadow(color: Palette.btnDrop, radius: 1, y: 1)
            }
            .contentShape(shape)
    }
}

extension ToolbarContent {
    /// Drops the shared Liquid Glass capsule macOS / iOS 26 put behind toolbar
    /// items, so an item looks as drawn. A no-op on earlier systems.
    @ToolbarContentBuilder
    func withoutSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
