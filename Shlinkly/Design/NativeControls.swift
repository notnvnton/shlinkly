//
//  NativeControls.swift
//  Shlinkly
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The window gets its calm look from *system* controls, the way Holds does:
// native push buttons, native segmented controls and switches, only tinted
// with the brand color. On macOS 26 / iOS 26 the system draws them in Liquid
// Glass; earlier systems get the bordered styles.

extension View {
    /// A native secondary button: Liquid Glass on 26+, `.bordered` below.
    @ViewBuilder
    func nativeButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A screen or state's one main action: prominent Liquid Glass on 26+,
    /// `.borderedProminent` below, tinted with the brand color either way.
    @ViewBuilder
    func nativeProminentButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glassProminent)
                .tint(Palette.accent)
        } else {
            buttonStyle(.borderedProminent)
                .tint(Palette.accent)
        }
    }

    /// A native segmented `Picker` whose selected segment is the brand color.
    /// The tint is applied first; on macOS a small bridge also sets the
    /// control's `selectedSegmentBezelColor`, which older macOS appearances
    /// need. iOS colors every segmented control once at launch
    /// (``NativeControlAppearance/configure()``).
    func brandSegmented() -> some View {
        #if os(macOS)
        tint(Palette.accent)
            .background(SegmentedBezelTint())
        #else
        tint(Palette.accent)
        #endif
    }
}

#if os(macOS)
/// Finds the `NSSegmentedControl` SwiftUI created for the picker it sits
/// behind, and colors its selected segment with `Brand`. The smallest bridge
/// there is: the native control is left as it is, only that one property is
/// set. Looks no further than a few ancestors up, so it can't reach another
/// picker. AppKit documents the property as applying "in appearances that
/// support it", so a system appearance may ignore it.
private struct SegmentedBezelTint: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        // SwiftUI may rebuild the control on an update; re-apply after it has.
        DispatchQueue.main.async { (view as? ProbeView)?.applyTint() }
    }

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTint()
        }

        func applyTint() {
            guard let control = nearestSegmentedControl() else { return }
            let brand = NSColor(named: "Brand")
            if control.selectedSegmentBezelColor != brand {
                control.selectedSegmentBezelColor = brand
            }
        }

        private func nearestSegmentedControl() -> NSSegmentedControl? {
            var ancestor = superview
            for _ in 0..<4 {
                guard let current = ancestor else { return nil }
                if let found = Self.firstSegmentedControl(in: current) { return found }
                ancestor = current.superview
            }
            return nil
        }

        private static func firstSegmentedControl(in view: NSView) -> NSSegmentedControl? {
            if let control = view as? NSSegmentedControl { return control }
            for subview in view.subviews {
                if let found = firstSegmentedControl(in: subview) { return found }
            }
            return nil
        }
    }
}
#endif

#if os(iOS)
/// App-wide appearance for the UIKit controls SwiftUI builds on.
enum NativeControlAppearance {
    /// Colors every segmented control's selected segment with `Brand`: white
    /// text on the light `#5249A8`, `#141318` text on the dark `#B3ACE6`. Call
    /// once at launch, before any picker is created.
    static func configure() {
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = UIColor(named: "Brand")
        let selectedText = UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x14 / 255, green: 0x13 / 255, blue: 0x18 / 255, alpha: 1)
                : .white
        }
        control.setTitleTextAttributes([.foregroundColor: selectedText], for: .selected)
    }
}
#endif
