//
//  MacTitleRow.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit

/// One of the Mac window's drawn header rows (`MacMain`): the sidebar panel's
/// 44 pt top row and the list and detail columns' 52 pt rows. The window has
/// no system title or toolbar (`.hiddenTitleBar`, toolbar hidden), so these
/// rows are the title bar:
///
/// - **On the traffic lights' line.** The system decides where the traffic
///   lights sit, and that differs between macOS versions, so the row reads it
///   from the window (the close button's center) and moves its content onto
///   that line. In full screen (no traffic lights) and in previews the row
///   keeps the drawn position: centered in its own height.
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
        var metrics = TitleRowMetrics()
        if !window.styleMask.contains(.fullScreen),
           let close = window.standardWindowButton(.closeButton),
           let zoom = window.standardWindowButton(.zoomButton),
           !close.isHidden, close.window === window {
            // Window coordinates count up from the bottom.
            let height = window.frame.height
            let closeRect = close.convert(close.bounds, to: nil)
            let zoomRect = zoom.convert(zoom.bounds, to: nil)
            let mine = convert(bounds, to: nil)
            let lightsCenter = height - closeRect.midY
            let top = height - mine.maxY
            metrics.topOffset = (lightsCenter - top - rowHeight / 2).rounded()
            let trailing = zoomRect.maxX - mine.minX
            metrics.lightsTrailing = trailing > 0 && zoomRect.minY >= mine.minY ? trailing.rounded() : nil
        }
        guard metrics != last else { return }
        last = metrics
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(metrics)
        }
    }
}
#endif
