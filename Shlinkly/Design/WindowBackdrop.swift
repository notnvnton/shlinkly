//
//  WindowBackdrop.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit

/// An `NSVisualEffectView` that blurs what is *behind the window* (the desktop,
/// other apps), following the window's active state: the `.win` class's
/// `backdrop-filter: blur(40px) saturate(160%)`.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = .underWindowBackground
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// `.win`: the Mac window as one continuous surface. The behind-window blur
/// with the flat `--win` wash over it, under every column and the title bar.
struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Palette.win
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// `.msidebar` below macOS 26: the floating sidebar panel. `--sidebar`,
/// radius 12, a 0.5 pt `--sidebar-edge` ring and `0 1 3` at 6%, inset 8 pt from
/// the window's top, bottom and leading edges. From macOS 26 the system's own
/// floating glass sidebar is that panel.
struct SidebarPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape
            .fill(Palette.sidebar)
            .overlay { shape.strokeBorder(Palette.sidebarEdge, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
            .padding([.top, .bottom, .leading], 8)
            .accessibilityHidden(true)
    }
}

/// `.mrow.sel`: the pastel pill behind a selected Mac list or sidebar row,
/// radius 8. A hovered row shows it at 40% (hover isn't drawn; it keeps the
/// pre-v3 behavior in the layout's color).
struct MacRowBackground: View {
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.sel)
            .opacity(isSelected ? 1 : (isHovering ? 0.4 : 0))
            .accessibilityHidden(true)
    }
}
#endif

#if os(macOS)
/// The sidebar toggle as `MacMain` draws it: a `.mbtn-sq` with no fill or
/// shadow, the sidebar glyph in `--text2`. It replaces the system's toggle.
struct SidebarToggleButton: View {
    /// Whether the sidebar is showing, for the label and help text.
    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .regular))
        }
        .buttonStyle(.macGhostSquare)
        .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
    }
}
#endif
