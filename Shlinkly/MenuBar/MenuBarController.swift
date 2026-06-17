//
//  MenuBarController.swift
//  Shlinkly
//

#if os(macOS)
import AppKit
import UserNotifications
import os
import ShlinklyCore

/// Owns and drives Shlinkly's menu-bar presence as a hand-managed `NSStatusItem`
/// (replacing SwiftUI's `MenuBarExtra`). The status item is AppKit-native so its
/// icon can later be animated directly (spin / fly-away) — something `MenuBarExtra`
/// can't do. This part is a behaviour-preserving migration: the menu structure,
/// the "Generate from clipboard" flow, and "Open"/"Quit" match the old
/// `MenuBarContent` exactly. No animation yet.
///
/// It holds the *same* ``AppModel`` the rest of the app uses (injected by
/// ``AppDelegate``), so it reads the one active server / ``ShlinkClient`` — no
/// second client, no singleton model.
@MainActor
final class MenuBarController: NSObject {
    /// The shared app state, injected (never a singleton). The active server's
    /// `client` is read from here when generating.
    private let appModel: AppModel

    /// The status item. Held strongly for the app's lifetime — the system doesn't
    /// keep it alive for us.
    private let statusItem: NSStatusItem

    /// The dropdown, rebuilt on every open (and live, if open, when state changes).
    private let menu = NSMenu()

    /// Outcome of the last "Generate from clipboard". Shown as a disabled row so the
    /// feedback survives the menu closing on click; `nil` until the command has run.
    /// Part 2 (animation) keys off these, which is why they're controller state now.
    private(set) var status: Status? {
        didSet { rebuildMenuIfOpen() }
    }
    /// True while a create is in flight, to disable re-entry and relabel the row.
    private(set) var isGenerating = false {
        didSet { rebuildMenuIfOpen() }
    }

    /// Whether the menu is currently shown, so state changes can refresh it live;
    /// otherwise the next `menuNeedsUpdate` (on open) picks the new state up.
    private var isMenuOpen = false

    private let log = Logger(subsystem: "de.ahodge.shlinkly", category: "MenuBar")

    /// What the status row reports.
    enum Status: Equatable {
        case created(String)
        case noURL
        case failed(String)

        var message: String {
            switch self {
            case .created(let shortURL): return "Copied \(shortURL)"
            case .noURL: return "No URL in clipboard"
            case .failed(let message): return message
            }
        }
    }

    init(appModel: AppModel) {
        self.appModel = appModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItemButton()
        menu.delegate = self
        menu.autoenablesItems = false   // honour our explicit isEnabled flags literally
        statusItem.menu = menu
        rebuildMenu()                   // safety: never display an empty menu pre-update
        log.info("status item created")
    }

    // MARK: - Status item button

    /// The brand chevrons as a template image — the system tints it for light/dark
    /// and menu highlight, exactly as the old SwiftUI `Image(...).renderingMode(.template)`.
    private func configureStatusItemButton() {
        guard let button = statusItem.button else {
            log.error("status item has no button")
            return
        }
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            log.error("MenuBarIcon asset missing")
        }
        button.setAccessibilityLabel("Shlinkly")
    }

    // MARK: - Menu construction

    /// Rebuilds the dropdown to match current state, 1:1 with the old `MenuBarContent`:
    /// optional status row → server-gated generate action → Open → Quit.
    private func rebuildMenu() {
        menu.removeAllItems()

        if let status {
            menu.addItem(disabledItem(title: status.message))
            menu.addItem(.separator())
        }

        if appModel.client == nil {
            // No server configured (or its key is unavailable): nothing to create
            // against, so the action is replaced by a clear, inert line.
            menu.addItem(disabledItem(title: "No server — add one in Shlinkly"))
        } else {
            let title = isGenerating ? "Generating…" : "Generate from clipboard"
            let item = NSMenuItem(title: title, action: #selector(generateClicked), keyEquivalent: "")
            item.target = self
            item.isEnabled = !isGenerating
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Shlinkly", action: #selector(openClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Quit Shlinkly", action: #selector(quitClicked), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    /// A non-interactive informational row.
    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Live-refresh only while the menu is on screen; otherwise the next open's
    /// `menuNeedsUpdate` rebuilds with the latest state.
    private func rebuildMenuIfOpen() {
        guard isMenuOpen else { return }
        rebuildMenu()
    }

    // MARK: - Actions

    @objc private func openClicked() {
        log.info("Open Shlinkly clicked")
        MacWindowManager.shared.showMainWindow()
    }

    @objc private func quitClicked() {
        log.info("Quit Shlinkly clicked")
        NSApp.terminate(nil)
    }

    @objc private func generateClicked() {
        generateFromClipboard()
    }

    // MARK: - Generate from clipboard

    /// Reads the clipboard, and if it holds a URL, creates a short link for it,
    /// copies the result back, and reports the outcome. All failure paths are soft —
    /// they set ``status`` rather than throwing into the UI. Ported verbatim from the
    /// old `MenuBarContent`; the state now lives on the controller.
    private func generateFromClipboard() {
        guard let client = appModel.client else { return }
        guard let longURL = Clipboard.peekURLString() else {
            status = .noURL
            return
        }
        isGenerating = true
        log.info("generate from clipboard: start")
        // `Task {}` from this @MainActor context runs on the main actor, so updating
        // `status` / `isGenerating` afterwards is safe; only the `client` call hops.
        Task {
            defer {
                isGenerating = false
                log.info("generate from clipboard: finished")
            }
            do {
                let shortURL = try await LinkActions.createShortURL(fromLongURL: longURL, using: client)
                Clipboard.copy(shortURL.shortUrl)
                status = .created(shortURL.shortUrl)
                log.info("generate from clipboard: success — \(shortURL.shortUrl, privacy: .public)")
                MenuBarNotifier.notify(title: "Short link copied", body: shortURL.shortUrl)
            } catch {
                let message = ShlinkError.userFacingMessage(for: error)
                status = .failed(message)
                log.error("generate from clipboard: failed — \(message, privacy: .public)")
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    /// AppKit calls this just before the menu is shown — rebuild so the status row,
    /// the server-gated action, and "Generating…" reflect the latest state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        log.info("menu opened")
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }
}

/// Best-effort transient feedback via a local notification.
///
/// Authorization is requested without blocking; if it's denied (or never granted)
/// the post simply no-ops, leaving the menu's status row as the guaranteed feedback.
/// Kept separate so the controller stays free of notification plumbing.
enum MenuBarNotifier {
    static func notify(title: String, body: String) {
        // Re-fetch the center inside the (Sendable) closure rather than capturing it,
        // so nothing non-Sendable crosses the boundary.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}
#endif
