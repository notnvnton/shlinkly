//
//  MatteButtonStyle.swift
//  Shlinkly
//

import SwiftUI

/// The convex matte button of the macOS window (approved mockup): a soft top-to-
/// bottom fill, a 0.5 pt top highlight, a 0.5 pt edge and a small shadow.
/// Pressing darkens the fill 4% and flattens the shadow; hovering (macOS)
/// brightens the highlight. Used for every button in the Mac window content —
/// action tiles, the chart's paging arrows, the row hover actions, empty- and
/// error-state buttons. The iPhone keeps its flat build-1 look.
struct MatteButtonStyle: ButtonStyle {
    enum Kind {
        /// Light fill, primary text.
        case secondary
        /// Brand fill, white label.
        case primary
    }

    var kind: Kind = .secondary
    /// The button's minimum height. 28 pt by default; action tiles pass their
    /// own.
    var minHeight: CGFloat = 28
    /// `nil` sizes the button to its label plus 12 pt on each side; a value
    /// makes it a fixed-width square-ish icon button.
    var width: CGFloat?
    var cornerRadius: CGFloat = Radius.control
    /// Draws the pressed state at rest. Only for the canvas preview.
    fileprivate var drawsPressed = false

    init(kind: Kind = .secondary, minHeight: CGFloat = 28, width: CGFloat? = nil,
         cornerRadius: CGFloat = Radius.control) {
        self.kind = kind
        self.minHeight = minHeight
        self.width = width
        self.cornerRadius = cornerRadius
    }

    /// This style, drawn pressed at rest.
    fileprivate func pressed() -> MatteButtonStyle {
        var copy = self
        copy.drawsPressed = true
        return copy
    }

    func makeBody(configuration: Configuration) -> some View {
        MatteButtonBody(configuration: configuration, kind: kind, minHeight: minHeight,
                        width: width, cornerRadius: cornerRadius, drawsPressed: drawsPressed)
    }
}

extension ButtonStyle where Self == MatteButtonStyle {
    /// The secondary matte button.
    static var matte: MatteButtonStyle { MatteButtonStyle() }
    /// The primary (brand-filled) matte button.
    static var matteProminent: MatteButtonStyle { MatteButtonStyle(kind: .primary) }
    /// A square matte icon button, `side` points on each side.
    static func matteIcon(side: CGFloat = 28) -> MatteButtonStyle {
        MatteButtonStyle(minHeight: side, width: side)
    }
}

/// The colors of the two matte kinds. Light and dark, top to bottom.
private enum MatteColors {
    static let secondaryTop = Color(light: hex(0xFFFFFF), dark: hex(0x4D4A5A))
    static let secondaryBottom = Color(light: hex(0xF1F0F6), dark: hex(0x3F3C4B))
    static let primaryTop = Color(light: hex(0x635CA8), dark: hex(0x6A63A6))
    static let primaryBottom = Color(light: hex(0x4A448C), dark: hex(0x4E4880))

    /// The 0.5 pt edge: black 11% in light mode, none in dark mode.
    static let edge = Color(light: rgba(0, 0, 0, 0.11), dark: rgba(0, 0, 0, 0))
}

private struct MatteButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: MatteButtonStyle.Kind
    let minHeight: CGFloat
    let width: CGFloat?
    let cornerRadius: CGFloat
    let drawsPressed: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let pressed = configuration.isPressed || drawsPressed
        configuration.label
            .foregroundStyle(kind == .primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(Palette.textPrimary))
            .lineLimit(1)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width)
            .frame(minHeight: minHeight)
            .background {
                shape
                    .fill(fill)
                    // Pressed: the fill darkens 4%.
                    .brightness(pressed ? -0.04 : 0)
                    .overlay {
                        // The 0.5 pt top highlight, fading out down the sides.
                        shape.strokeBorder(
                            LinearGradient(colors: [highlight, highlight.opacity(0)],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 0.5
                        )
                    }
                    .overlay { shape.strokeBorder(MatteColors.edge, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(pressed ? 0 : shadowOpacity),
                            radius: pressed ? 0 : 1.5, y: pressed ? 0 : 1)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            #if os(macOS)
            .onHover { isHovering = $0 }
            #endif
            .animation(.spring(duration: 0.18), value: pressed)
            .animation(.spring(duration: 0.18), value: isHovering)
    }

    private var fill: LinearGradient {
        let colors = kind == .primary
            ? [MatteColors.primaryTop, MatteColors.primaryBottom]
            : [MatteColors.secondaryTop, MatteColors.secondaryBottom]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// White 95% (light) / 12% (dark) on the secondary kind, 28% on the
    /// primary one; full white while hovered.
    private var highlight: Color {
        if isHovering && isEnabled { return .white }
        switch kind {
        case .primary: return .white.opacity(0.28)
        case .secondary: return .white.opacity(colorScheme == .dark ? 0.12 : 0.95)
        }
    }

    /// 10% in light mode, 35% in dark mode.
    private var shadowOpacity: Double { colorScheme == .dark ? 0.35 : 0.10 }
}

#if DEBUG
private struct MatteButtonsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button("Secondary") {}
                    .buttonStyle(.matte)
                Button("Primary") {}
                    .buttonStyle(.matteProminent)
                Button {} label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.matteIcon())
                Button("Disabled") {}
                    .buttonStyle(.matte)
                    .disabled(true)
            }
            HStack(spacing: 10) {
                Text("Pressed:")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Button("Secondary") {}
                    .buttonStyle(MatteButtonStyle(kind: .secondary).pressed())
                Button("Primary") {}
                    .buttonStyle(MatteButtonStyle(kind: .primary).pressed())
            }
        }
        .padding(24)
    }
}

#Preview("Matte buttons, light") {
    MatteButtonsPreview()
        .canvasBackground()
        .preferredColorScheme(.light)
}

#Preview("Matte buttons, dark") {
    MatteButtonsPreview()
        .canvasBackground()
        .preferredColorScheme(.dark)
}
#endif
