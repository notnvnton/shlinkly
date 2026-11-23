//
//  WindowBackdrop.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit

/// An `NSVisualEffectView` that blurs what is *behind the window* (the desktop,
/// other apps), following the window's active state. The same path on macOS
/// 14.6 and later: `containerBackground(_:for: .window)` (macOS 15) can't pick
/// the `.underWindowBackground` material.
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// The translucent matte window: the behind-window blur with the soft lavender
/// wash over it. The list and detail columns sit straight on it (no opaque
/// canvas on macOS).
struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Palette.Mac.windowWash
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The sidebar column: the system sidebar material with a lavender wash.
struct SidebarBackdrop: View {
    var body: some View {
        ZStack {
            BehindWindowBlur(material: .sidebar)
            Palette.Mac.sidebarWash
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The soft lavender selection pill behind a selected list or sidebar row:
/// inset 8 pt from the column's sides, radius 8, with a 0.5 pt brand edge. A
/// hovered unselected row shows it at 40%.
struct SelectionPill: View {
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(Palette.Mac.selectionFill)
            .overlay(shape.strokeBorder(Palette.Mac.selectionEdge, lineWidth: 0.5))
            .opacity(isSelected ? 1 : (isHovering ? 0.4 : 0))
            .padding(.horizontal, 8)
            .animation(.spring(duration: 0.22), value: isSelected)
            .animation(.spring(duration: 0.22), value: isHovering)
            .accessibilityHidden(true)
    }
}
#endif
