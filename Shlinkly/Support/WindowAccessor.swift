//
//  WindowAccessor.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit

/// Captures the `NSWindow` backing a SwiftUI scene's view the moment that view is
/// mounted into the window hierarchy, and hands it to a callback.
///
/// This is how we get a reference to the *main* window without guessing by title
/// or identifier: place it in the `Window` scene's view tree and the window we
/// resolve is, by construction, the one hosting that scene. Attach it as a
/// `.background(...)` on the main scene's root view.
struct WindowAccessor: NSViewRepresentable {
    /// Invoked once, on the main actor, with the resolved window. The view itself
    /// lives only to find the window — it draws nothing.
    let onResolve: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowResolvingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// A zero-size `NSView` that reports its hosting window the moment it joins the
    /// hierarchy. `view.window` is `nil` until then, so resolving in
    /// `viewDidMoveToWindow` (rather than at `makeNSView` time) is what makes the
    /// capture reliable.
    private final class WindowResolvingView: NSView {
        var onResolve: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // AppKit delivers this on the main thread; assert that isolation so the
            // main-actor callback can run synchronously without a hop.
            MainActor.assumeIsolated {
                onResolve?(window)
            }
        }
    }
}
#endif
