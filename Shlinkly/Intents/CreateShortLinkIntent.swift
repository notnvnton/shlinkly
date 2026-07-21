//
//  CreateShortLinkIntent.swift
//  Shlinkly
//

import AppIntents
import Foundation
import ShlinklyCore

/// Shortens a long URL from Shortcuts or Siri and hands the short URL back as
/// the intent's value, so it can be piped straight into the next action.
///
/// Deliberately thin: the server comes from ``ActiveServerResolver`` (the same
/// Keychain-only path the Share Extensions use — no ``AppModel``, no SwiftUI)
/// and the link itself from ``LinkActions/createShortURL(fromLongURL:using:)``,
/// so a link made here is identical to one made in the app.
struct CreateShortLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Create short link"
    static var description = IntentDescription(
        "Shortens a URL with your active Shlink server and returns the short link."
    )
    /// Runs entirely against the Keychain and the network — nothing to show, so
    /// Shortcuts shouldn't foreground the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Long URL")
    var longURL: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Create a short link for \(\.$longURL)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<URL> {
        let client: ShlinkClient
        do {
            client = try ActiveServerResolver.resolve().client
        } catch {
            throw CreateShortLinkError.noServer
        }

        let created: ShortURL
        do {
            created = try await LinkActions.createShortURL(fromLongURL: longURL.absoluteString, using: client)
        } catch {
            throw CreateShortLinkError.createFailed(ShlinkError.userFacingMessage(for: error))
        }

        guard let shortURL = URL(string: created.shortUrl) else {
            throw CreateShortLinkError.createFailed("The server returned a short link that couldn't be read.")
        }
        return .result(value: shortURL)
    }
}

/// Failures surfaced to Shortcuts / Siri as readable sentences rather than a
/// bare `Error`, which the system would otherwise report as "the operation
/// couldn't be completed".
enum CreateShortLinkError: Error, CustomLocalizedStringResourceConvertible {
    /// No usable server in the Keychain — none configured, an ambiguous list, or
    /// a missing API key. One message, because the fix is the same: open the app.
    case noServer
    /// The server was reached but the link wasn't created; carries the reason.
    case createFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noServer:
            return "No Shlink server is configured. Open Shlinkly and add one first."
        case .createFailed(let reason):
            return "Could not create the short link. \(reason)"
        }
    }
}
