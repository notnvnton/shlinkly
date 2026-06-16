//
//  ShareCreateView.swift
//  Shared by ShareExtensionIOS and ShareExtensionMac.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ShlinklyCore

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The one screen both Share Extensions show. Zero-tap by design: on appear it
/// resolves the active server, creates the short link, copies it, and shows the
/// result — no Create button, no server/tags pickers (v1). Talks only to
/// ``ActiveServerResolver`` and ``ShlinkClient`` — no `AppModel`, no stores, so
/// it runs the same in the extension's separate process.
struct ShareCreateView: View {
    /// The URL being shared (already extracted from the host by the controller).
    let longURL: String
    /// Closes the extension (the host calls `completeRequest`).
    let onDone: () -> Void

    /// Bumped by Retry to re-run the resolve+create task via `.task(id:)`.
    @State private var attempt = 0
    @State private var state: ShareState = .creating(serverName: nil)

    var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .creating(let serverName):
                creatingView(serverName: serverName)
            case .success(let shortURL):
                successView(shortURL: shortURL)
            case .error(let title, let subtitle, let canRetry):
                errorView(title: title, subtitle: subtitle, canRetry: canRetry)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: attempt) { await run() }
    }

    // MARK: - Flow

    /// Resolve the active server, then create the short link. Each step maps its
    /// failure onto a specific ``ShareState/error`` so the UI says the right
    /// thing; a non-fatal create failure offers Retry.
    @MainActor
    private func run() async {
        state = .creating(serverName: nil)

        let resolved: (instance: ServerInstance, client: ShlinkClient)
        do {
            resolved = try ActiveServerResolver.resolve()
        } catch ActiveServerError.noActiveServer {
            state = .error(title: "No server set up.",
                           subtitle: "Open Shlinkly to add a server.",
                           canRetry: false)
            return
        } catch ActiveServerError.missingKey {
            state = .error(title: "Couldn't find the server key.",
                           subtitle: "Re-add the server in Shlinkly.",
                           canRetry: false)
            return
        } catch {
            state = .error(title: "Couldn't create the short link.",
                           subtitle: ShlinkError.userFacingMessage(for: error),
                           canRetry: true)
            return
        }

        state = .creating(serverName: resolved.instance.displayName)

        do {
            let created = try await resolved.client.createShortURL(fromLongURL: longURL)
            ShareClipboard.copy(created.shortUrl)
            state = .success(shortURL: created.shortUrl)
        } catch {
            state = .error(title: "Couldn't create the short link.",
                           subtitle: ShlinkError.userFacingMessage(for: error),
                           canRetry: true)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func creatingView(serverName: String?) -> some View {
        routeLabel(serverName: serverName)
        ProgressView()
        Text("Creating short link…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func routeLabel(serverName: String?) -> some View {
        HStack(spacing: 6) {
            Text(longURL)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            if let serverName {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(serverName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func successView(shortURL: String) -> some View {
        Text(shortURL)
            .font(.system(.title3, design: .monospaced))
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .onTapGesture { ShareClipboard.copy(shortURL) }
        Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Button("Done", action: onDone)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private func errorView(title: String, subtitle: String, canRetry: Bool) -> some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.title)
            .foregroundStyle(.secondary)
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.center)
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        HStack(spacing: 12) {
            if canRetry {
                Button("Retry") { attempt += 1 }
            }
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 4)
    }
}

/// The screen's three states. `.creating` carries the resolved server name once
/// known (nil during the instant before resolution).
enum ShareState {
    case creating(serverName: String?)
    case success(shortURL: String)
    case error(title: String, subtitle: String, canRetry: Bool)
}

/// Copies a string to the system pasteboard, per platform.
enum ShareClipboard {
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

/// Pulls the shared web URL out of the extension's input items.
enum ShareItemReader {
    /// Returns the first `public.url` attachment as a string, or `nil` when the
    /// share carried no URL. Never throws — callers treat `nil` as "nothing to do".
    static func extractURL(from context: NSExtensionContext?) async -> String? {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return nil }
        let urlType = UTType.url.identifier
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(urlType) {
                guard let loaded = try? await provider.loadItem(forTypeIdentifier: urlType) else { continue }
                if let url = loaded as? URL { return url.absoluteString }
                if let nsurl = loaded as? NSURL { return nsurl.absoluteString }
                if let data = loaded as? Data, let string = String(data: data, encoding: .utf8) { return string }
                if let string = loaded as? String { return string }
            }
        }
        return nil
    }
}
