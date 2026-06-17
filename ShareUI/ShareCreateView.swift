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
#if os(macOS)
import os
#endif

/// The one screen both Share Extensions show. Zero-tap by design: on appear it
/// resolves the active server, creates the short link, copies it, and shows the
/// result with a Done button — no Create button, no server/tags pickers (v1).
/// The extra action differs by platform: iOS adds Share (the native share
/// sheet), macOS adds Open in Shlinkly (Apple bars iOS share extensions from
/// launching their host app). Talks only to ``ActiveServerResolver`` and
/// ``ShlinkClient`` — no `AppModel`, no stores — so it runs the same in the
/// extension's separate process. Platform-specific actions are injected by the
/// host as closures.
struct ShareCreateView: View {
    /// The URL being shared (already extracted from the host by the controller).
    let longURL: String
    /// Closes the extension (the host calls `completeRequest`).
    let onDone: () -> Void
    /// macOS only: opens a `shlinkly://` deep link in the main app (via
    /// `NSWorkspace`), then closes the extension. On iOS this stays the no-op
    /// default — Apple doesn't allow a share extension to launch its host app, so
    /// the iOS host doesn't pass it. A `var` with a default so the synthesized
    /// memberwise initializer exposes it as optional (a `let` with a default is
    /// excluded from that initializer).
    var onOpenInApp: (URL) -> Void = { _ in }

    /// Bumped by Retry to re-run the resolve+create task via `.task(id:)`.
    @State private var attempt = 0
    @State private var state: ShareState = .creating(serverName: nil)
    /// Drives the "compression" pulse on the creating indicator.
    @State private var compressing = false
    /// Toggled on the success checkmark's appearance to fire its bounce.
    @State private var checkBounce = false

    var body: some View {
        ZStack {
            switch state {
            case .creating(let serverName):
                creatingView(serverName: serverName)
                    .transition(.opacity)
            case .success(let shortURL, let shortCode):
                successView(shortURL: shortURL, shortCode: shortCode)
                    .transition(.opacity.combined(with: .scale))
            case .error(let title, let subtitle, let canRetry):
                errorView(title: title, subtitle: subtitle, canRetry: canRetry)
                    .transition(.opacity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: attempt) { await run() }
    }

    // MARK: - Flow

    /// Resolve the active server, then create the short link. Each step maps its
    /// failure onto a specific ``ShareState/error`` so the UI says the right
    /// thing; a non-fatal create failure offers Retry. The creating→success flip
    /// is animated with a spring.
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
            #if os(macOS)
            ShareSignal.started()
            #endif
            let created = try await resolved.client.createShortURL(fromLongURL: longURL)
            ShareClipboard.copy(created.shortUrl)
            #if os(macOS)
            ShareSignal.succeeded()
            #endif
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                state = .success(shortURL: created.shortUrl, shortCode: created.shortCode)
            }
        } catch {
            #if os(macOS)
            ShareSignal.failed()
            #endif
            state = .error(title: "Couldn't create the short link.",
                           subtitle: ShlinkError.userFacingMessage(for: error),
                           canRetry: true)
        }
    }

    // MARK: - Creating

    private func creatingView(serverName: String?) -> some View {
        VStack(spacing: 20) {
            routeLabel(serverName: serverName)

            // A narrow capsule that rhythmically shrinks and grows — the
            // "shortening" metaphor while the link is being made.
            Capsule()
                .fill(.tint)
                .frame(width: compressing ? 36 : 168, height: 8)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: compressing)
                .onAppear { compressing = true }
                .onDisappear { compressing = false }

            Text("Creating short link…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func routeLabel(serverName: String?) -> some View {
        HStack(spacing: 6) {
            Text(longURL)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            if let serverName {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(serverName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
    }

    // MARK: - Success

    private func successView(shortURL: String, shortCode: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .nonRepeating, value: checkBounce)
            }
            .onAppear { checkBounce = true }

            Text("Short link ready")
                .font(.headline)

            Text(shortURL)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.4))
                )
                .contentShape(Rectangle())
                .onTapGesture { ShareClipboard.copy(shortURL) }

            Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            successActions(shortURL: shortURL, shortCode: shortCode)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func successActions(shortURL: String, shortCode: String) -> some View {
        #if os(iOS)
        // iOS: Share via the native share sheet (ShareLink works here), then Done.
        // No "Open in Shlinkly" — Apple doesn't allow a share extension to launch
        // its host app. The short URL is also already on the clipboard.
        VStack(spacing: 10) {
            if let url = URL(string: shortURL) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Done", action: onDone)
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
        }
        #else
        // macOS: no Share button. SwiftUI ShareLink comes up empty in a sandboxed
        // share extension, and macOS share extensions can't reach the messengers
        // people actually want (WhatsApp/Telegram aren't offered). The short URL is
        // already on the clipboard, so the user can paste it anywhere — we just
        // offer Open in Shlinkly and Done, stacked full-width in the app's
        // Save/Cancel style (.controlSize(.large)); Done is the prominent action.
        VStack(spacing: 10) {
            if let deepLink = deepLink(shortCode: shortCode) {
                Button {
                    onOpenInApp(deepLink)
                } label: {
                    Label("Open in Shlinkly", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                onDone()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        #endif
    }

    /// `shlinkly://link/{shortCode}` — the deep link the main app will route to a
    /// link's detail (routing lands in a later slice; here it just launches the app).
    private func deepLink(shortCode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shlinkly"
        components.host = "link"
        components.path = "/" + shortCode
        return components.url
    }

    // MARK: - Error

    private func errorView(title: String, subtitle: String, canRetry: Bool) -> some View {
        VStack(spacing: 12) {
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
}

/// The screen's three states. `.creating` carries the resolved server name once
/// known (nil during the instant before resolution); `.success` carries both the
/// short URL (to show/copy/share) and its short code (to build the deep link).
enum ShareState {
    case creating(serverName: String?)
    case success(shortURL: String, shortCode: String)
    case error(title: String, subtitle: String, canRetry: Bool)
}

#if os(macOS)
/// macOS Share Extension only: posts the cross-process generation Darwin signal and
/// logs it, so on-device you can see whether the extension fired each step. The
/// app's `MenuBarController` receives these and drives the menu-bar icon. iOS has no
/// menu bar, so this is compiled out there.
private enum ShareSignal {
    private static let log = Logger(subsystem: "de.ahodge.shlinkly", category: "ShareSignal")

    static func started() {
        log.info("post: started")
        postGenerationSignal(GenerationSignal.started)
    }
    static func succeeded() {
        log.info("post: succeeded")
        postGenerationSignal(GenerationSignal.succeeded)
    }
    static func failed() {
        log.info("post: failed")
        postGenerationSignal(GenerationSignal.failed)
    }
}
#endif

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
