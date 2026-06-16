//
//  MenuBarContent.swift
//  Shlinkly
//

#if os(macOS)
import SwiftUI
import AppKit
import UserNotifications
import ShlinklyCore

/// The macOS menu-bar dropdown's contents: a one-shot "Generate from clipboard",
/// plus "Open" and "Quit".
///
/// It lives in the same process as the main window, so it reads the *same*
/// ``AppModel`` (and its active server / ``ShlinkClient``) the app is already
/// using — there's no second client or second copy of the credentials.
struct MenuBarContent: View {
    /// The shared app state. Passed in (rather than read from the environment)
    /// because a `MenuBarExtra` scene doesn't inherit the `WindowGroup`'s
    /// environment.
    let appModel: AppModel

    /// Outcome of the last "Generate from clipboard". Shown as a disabled status
    /// row so the feedback survives the menu closing on click; `nil` until the
    /// command has run at least once.
    @State private var status: Status?
    /// True while a create is in flight, to disable re-entry and label the row.
    @State private var isGenerating = false

    /// What the status row reports.
    private enum Status: Equatable {
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

    var body: some View {
        if let status {
            Text(status.message)
            Divider()
        }

        if appModel.client == nil {
            // No server configured (or its key is unavailable): nothing to create
            // against, so the action is replaced by a clear, inert status line.
            Text("No server — add one in Shlinkly")
        } else {
            Button(isGenerating ? "Generating…" : "Generate from clipboard") {
                generateFromClipboard()
            }
            .disabled(isGenerating)
        }

        Divider()

        Button("Open Shlinkly") { openMainWindow() }
        Button("Quit Shlinkly") { NSApp.terminate(nil) }
    }

    /// Reads the clipboard, and if it holds a URL, creates a short link for it,
    /// copies the result back, and reports the outcome. All failure paths are
    /// handled softly — they set ``status`` rather than throwing into the UI.
    private func generateFromClipboard() {
        guard let client = appModel.client else { return }
        guard let longURL = Clipboard.peekURLString() else {
            status = .noURL
            return
        }
        isGenerating = true
        // `Task {}` from this @MainActor view runs on the main actor, so updating
        // `status` / `isGenerating` afterwards is safe; only the `client` call
        // hops to the actor.
        Task {
            defer { isGenerating = false }
            do {
                let shortURL = try await LinkActions.createShortURL(fromLongURL: longURL, using: client)
                Clipboard.copy(shortURL.shortUrl)
                status = .created(shortURL.shortUrl)
                MenuBarNotifier.notify(title: "Short link copied", body: shortURL.shortUrl)
            } catch {
                status = .failed(ShlinkError.userFacingMessage(for: error))
            }
        }
    }

    /// Brings the app and its main window to the front, opening one if the user
    /// had closed it (the menu-bar item keeps the app running with no windows).
    /// Routes through the AppDelegate's single show path so the Dock icon is
    /// restored first — without it, AppKit won't let the window activate in
    /// menu-bar-only (accessory) mode.
    private func openMainWindow() {
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }
}

/// Best-effort transient feedback via a local notification.
///
/// Authorization is requested without blocking; if it's denied (or never
/// granted) the post simply no-ops, leaving the menu's status row as the
/// guaranteed feedback. Kept separate so the view stays free of notification
/// plumbing.
enum MenuBarNotifier {
    static func notify(title: String, body: String) {
        // Re-fetch the center inside the (Sendable) closure rather than capturing
        // it, so nothing non-Sendable crosses the boundary.
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
