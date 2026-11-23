//
//  MacTitleRow.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit

/// One of the Mac window's drawn header rows (`MacMain`): the sidebar panel's
/// 44 pt top row and the list and detail columns' 52 pt rows. The window has
/// no system title (`.hiddenTitleBar`) and an empty toolbar with no items, so
/// these rows are the title bar:
///
/// - **On the traffic lights' line.** The window keeps an empty unified
///   toolbar (installed here, see ``TitleRowChromeView/installEmptyToolbar``),
///   which puts the traffic lights 26 pt down, the drawn 52 pt row's center.
///   The row still reads the line from the window (the close button's
///   center) and moves its content onto it. When the buttons can't be seen
///   (full screen, previews) the line is 26 pt down, and it's never higher
///   than that, so nothing comes closer than 13 pt to the window's top edge.
/// - **Window chrome.** Its empty parts drag the window
///   (`performWindowDrag(with:)`, also on an inactive window) and a double
///   click does what System Settings › Desktop & Dock says a title-bar double
///   click does.
///
/// `content` gets the traffic lights' trailing edge in the row's own
/// coordinates, or `nil` when they aren't over this row, so the list header
/// can place the sidebar toggle after them when the sidebar is hidden.
struct MacTitleRow<Content: View>: View {
    private let height: CGFloat
    private let content: (_ lightsTrailing: CGFloat?) -> Content
    @State private var metrics = TitleRowMetrics()

    init(height: CGFloat, @ViewBuilder content: @escaping (_ lightsTrailing: CGFloat?) -> Content) {
        self.height = height
        self.content = content
    }

    var body: some View {
        content(metrics.lightsTrailing)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.top, metrics.topOffset)
            .background {
                TitleRowChrome(rowHeight: height) { metrics = $0 }
            }
    }
}

/// What a row reads from its window.
struct TitleRowMetrics: Equatable {
    /// The traffic lights' line, from the window's top edge, when they can't
    /// be read; also the highest the line may be.
    static let defaultCenter: CGFloat = 26

    /// How far the row moves down (or up) from the top of its column so its
    /// center is on the traffic lights' line.
    var topOffset: CGFloat = 0
    /// The zoom button's trailing edge, from the row's leading edge.
    var lightsTrailing: CGFloat?
}

/// The AppKit view behind a ``MacTitleRow``: measures the traffic lights
/// against itself and makes the row's empty parts behave like a title bar.
private struct TitleRowChrome: NSViewRepresentable {
    let rowHeight: CGFloat
    let onChange: (TitleRowMetrics) -> Void

    func makeNSView(context: Context) -> TitleRowChromeView {
        let view = TitleRowChromeView()
        view.rowHeight = rowHeight
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TitleRowChromeView, context: Context) {
        view.rowHeight = rowHeight
        view.onChange = onChange
        view.report()
    }
}

final class TitleRowChromeView: NSView {
    var rowHeight: CGFloat = 52
    var onChange: ((TitleRowMetrics) -> Void)?
    private var last: TitleRowMetrics?
    private var observers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    /// A drag works on an inactive window too, as in a real title bar.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            Self.performTitleBarDoubleClick(in: window)
        } else {
            window.performDrag(with: event)
        }
    }

    /// Whether `view` can actually be seen: neither it nor an ancestor is
    /// hidden or fully transparent. Hiding the window toolbar hides the
    /// buttons' container, not the buttons, so `isHidden` alone isn't enough.
    private static func isShowing(_ view: NSView) -> Bool {
        guard !view.isHiddenOrHasHiddenAncestor else { return false }
        var current: NSView? = view
        while let candidate = current {
            if candidate.alphaValue <= 0.01 { return false }
            current = candidate.superview
        }
        return true
    }

    /// Gives the window an empty unified toolbar when it has none. SwiftUI
    /// installs no toolbar when there are no toolbar items (and hiding the
    /// window toolbar would hide the traffic lights with it); without one the
    /// traffic lights sit 16 pt down, in a 32 pt title bar. The empty toolbar
    /// makes the title bar 52 pt, with the traffic lights on its center line,
    /// as `MacMain` draws them. It has no items, so it draws nothing and
    /// takes no clicks; `.hiddenTitleBar` keeps its background transparent.
    /// View › Show/Hide Toolbar is removed from the menu (`ShlinklyApp`), so
    /// it can't be hidden.
    static func installEmptyToolbar(in window: NSWindow) {
        guard window.toolbar == nil else { return }
        let toolbar = NSToolbar(identifier: "de.ahodge.shlinkly.main.empty")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        // AppKit keeps the content size when a toolbar arrives, growing the
        // window; keep the frame instead, so a restored window doesn't grow
        // on every launch.
        let frame = window.frame
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        if !window.styleMask.contains(.fullScreen) {
            window.setFrame(frame, display: true)
        }
    }

    /// The system's title-bar double-click action (`AppleActionOnDoubleClick`
    /// in the global domain): minimize, nothing, or zoom (also for "Fill").
    private static func performTitleBarDoubleClick(in window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observe()
    }

    /// Measures again whenever the window changes, and whenever any ancestor
    /// view moves or resizes: hiding the sidebar moves the list column (an
    /// ancestor), not this view's own frame, and the list header's toggle
    /// must then move after the traffic lights.
    private func observe() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
        }
        var ancestor = superview
        while let view = ancestor {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
            ancestor = view.superview
        }
        report()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        report()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        report()
    }

    /// Measures and, when something changed, tells the row (on the next turn
    /// of the run loop, never during a SwiftUI update).
    func report() {
        guard let window else { return }
        if window.toolbar == nil {
            // Not during layout: adding a toolbar re-lays out the window.
            DispatchQueue.main.async { [weak window] in
                if let window { Self.installEmptyToolbar(in: window) }
            }
        }
        // Window coordinates count up from the bottom.
        let height = window.frame.height
        let mine = convert(bounds, to: nil)
        let top = height - mine.maxY
        var lightsCenter = TitleRowMetrics.defaultCenter
        var metrics = TitleRowMetrics()
        if !window.styleMask.contains(.fullScreen),
           let close = window.standardWindowButton(.closeButton),
           let zoom = window.standardWindowButton(.zoomButton),
           close.window === window, Self.isShowing(close) {
            let closeRect = close.convert(close.bounds, to: nil)
            let zoomRect = zoom.convert(zoom.bounds, to: nil)
            lightsCenter = max(height - closeRect.midY, TitleRowMetrics.defaultCenter)
            let trailing = zoomRect.maxX - mine.minX
            metrics.lightsTrailing = trailing > 0 && zoomRect.minY >= mine.minY ? trailing.rounded() : nil
        }
        metrics.topOffset = (lightsCenter - top - rowHeight / 2).rounded()
        guard metrics != last else { return }
        last = metrics
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(metrics)
        }
    }
}
#endif
