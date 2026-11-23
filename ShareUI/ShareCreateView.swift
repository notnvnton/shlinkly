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

/// The one screen both Share Extensions show (layout v3: `PhoneShareExt`).
/// Zero-tap by design: on appear it resolves the active server, creates the
/// short link, copies it, and shows the result with Done — no Create button, no
/// server/tags pickers (v1).
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
    /// Previews only: show this state instead of creating a link.
    var previewState: ShareState?

    /// Bumped by Retry to re-run the resolve+create task via `.task(id:)`.
    @State private var attempt = 0
    @State private var state: ShareState = .creating(serverName: nil)
    /// Drives the "compression" pulse on the creating indicator.
    @State private var compressing = false

    var body: some View {
        #if os(iOS)
        // `PhoneShareExt`: the "Shlinkly" title with Done, the result card, and
        // Share / Done at the bottom.
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Shlinkly")
                    .shareFont(17, .semibold)
                    .foregroundStyle(ShareTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .shareFont(17, .semibold)
                    .foregroundStyle(ShareTheme.brand)
                    .frame(minHeight: 44)
            }
            .frame(height: 44)
            .padding(.leading, 20)
            .padding(.trailing, 12)

            stateContent
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if case .success(let shortURL, _) = state {
                HStack(spacing: 12) {
                    if let url = URL(string: shortURL) {
                        ShareLink(item: url) {
                            Text("Share")
                        }
                        .buttonStyle(ShareLargeButtonStyle(primary: false))
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(ShareLargeButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .background { ShareTheme.bg.ignoresSafeArea() }
        .task(id: attempt) { await run() }
        #else
        ZStack {
            stateContent
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: attempt) { await run() }
        #endif
    }

    @ViewBuilder
    private var stateContent: some View {
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

    // MARK: - Flow

    /// Resolve the active server, then create the short link. Each step maps its
    /// failure onto a specific ``ShareState/error`` so the UI says the right
    /// thing; a non-fatal create failure offers Retry. The creating→success flip
    /// is animated with a spring.
    @MainActor
    private func run() async {
        if let previewState {
            state = previewState
            return
        }
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

    /// Not drawn; kept, in the layout's colors.
    private func creatingView(serverName: String?) -> some View {
        VStack(spacing: 20) {
            routeLabel(serverName: serverName)

            // A narrow capsule that rhythmically shrinks and grows — the
            // "shortening" metaphor while the link is being made.
            Capsule()
                .fill(ShareTheme.brand)
                .frame(width: compressing ? 36 : 168, height: 8)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: compressing)
                .onAppear { compressing = true }
                .onDisappear { compressing = false }

            Text("Creating short link…")
                .shareFont(13)
                .foregroundStyle(ShareTheme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func routeLabel(serverName: String?) -> some View {
        HStack(spacing: 6) {
            Text(longURL)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(ShareTheme.text2)
            if let serverName {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(ShareTheme.text2)
                Text(serverName)
                    .fontWeight(.semibold)
                    .foregroundStyle(ShareTheme.text)
                    .lineLimit(1)
            }
        }
        .shareFont(13)
    }

    // MARK: - Success

    /// The result card: a check with "Short link ready" (15 pt semibold), the
    /// short URL (17 pt medium, `--brand-text`; tap copies it again) and
    /// "Copied to clipboard." (13 pt `--text2`). `.card`, 16 pt in.
    private func successView(shortURL: String, shortCode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShareTheme.brand)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text("Short link ready")
                        .shareFont(15, .semibold)
                        .foregroundStyle(ShareTheme.text)
                }
                Text(displayURL(shortURL))
                    .shareFont(17, .medium)
                    .foregroundStyle(ShareTheme.brand)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture { ShareClipboard.copy(shortURL) }
                Text("Copied to clipboard.")
                    .shareFont(13)
                    .foregroundStyle(ShareTheme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ShareTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ShareTheme.cardBorder, lineWidth: 1)
            }

            #if os(macOS)
            macSuccessActions(shortCode: shortCode)
            #endif
        }
    }

    /// The short URL without its scheme, as the artboard shows it.
    private func displayURL(_ shortURL: String) -> String {
        shortURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    #if os(macOS)
    /// macOS (not drawn): no Share button. SwiftUI ShareLink comes up empty in a
    /// sandboxed share extension, and macOS share extensions can't reach the
    /// messengers people actually want. The short URL is already on the
    /// clipboard, so the user can paste it anywhere: Open in Shlinkly and Done,
    /// as `.mbtn` / `.mbtn-primary`.
    private func macSuccessActions(shortCode: String) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let deepLink = deepLink(shortCode: shortCode) {
                Button("Open in Shlinkly") { onOpenInApp(deepLink) }
                    .buttonStyle(ShareMacButtonStyle(primary: false))
            }
            Button("Done", action: onDone)
                .buttonStyle(ShareMacButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
        }
    }
    #endif

    /// `shlinkly://link/{shortCode}` — the deep link the main app will route to a
    /// link's detail.
    private func deepLink(shortCode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shlinkly"
        components.host = "link"
        components.path = "/" + shortCode
        return components.url
    }

    // MARK: - Error

    /// Not drawn; kept, in the layout's colors and buttons.
    private func errorView(title: String, subtitle: String, canRetry: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .shareFont(15, .semibold)
                .foregroundStyle(ShareTheme.text)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .shareFont(13)
                .foregroundStyle(ShareTheme.text2)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if canRetry {
                    #if os(macOS)
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(ShareMacButtonStyle(primary: false))
                    #else
                    Button("Retry") { attempt += 1 }
                        .buttonStyle(.plain)
                        .shareFont(16, .medium)
                        .foregroundStyle(ShareTheme.brand)
                        .frame(minHeight: 44)
                    #endif
                }
                #if os(macOS)
                Button("Done", action: onDone)
                    .buttonStyle(ShareMacButtonStyle(primary: true))
                #endif
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
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

// MARK: - Theme

/// The layout v3 tokens the share extensions use. They're separate targets that
/// don't build `Shlinkly/Design/Theme.swift`, so this is a minimal copy with the
/// same values: it mirrors `Palette` there (`theme.css`); change both together.
private enum ShareTheme {
    /// `--brand-text`.
    static let brand = adaptive(light: (0x43, 0x3C, 0x8C, 1), dark: (0xA9, 0xA3, 0xE6, 1))
    /// `--text`.
    static let text = adaptive(light: (0x16, 0x15, 0x1C, 1), dark: (0xED, 0xEC, 0xF2, 1))
    /// `--text2`.
    static let text2 = adaptive(light: (0x5D, 0x5B, 0x6E, 1), dark: (0xA2, 0xA0, 0xB0, 1))
    /// `--on-brand`.
    static let onBrand = adaptive(light: (0xFF, 0xFF, 0xFF, 1), dark: (0xEE, 0xED, 0xF5, 1))
    /// `--card`.
    static let card = adaptive(light: (0xFF, 0xFF, 0xFF, 1), dark: (255, 255, 255, 0.055))
    /// `--card-border`.
    static let cardBorder = adaptive(light: (0xE4, 0xE4, 0xEA, 1), dark: (255, 255, 255, 0.06))
    /// `--mbtn-border`.
    static let mbtnBorder = adaptive(light: (0xD9, 0xD9, 0xE1, 1), dark: (255, 255, 255, 0.06))
    /// `--btn-shadow` top highlight and drop.
    static let btnHighlight = adaptive(light: (255, 255, 255, 0.16), dark: (255, 255, 255, 0.08))
    static let btnDrop = adaptive(light: (40, 30, 90, 0.16), dark: (0, 0, 0, 0.30))
    /// `--btn2-shadow` top highlight and ring.
    static let btn2Highlight = adaptive(light: (255, 255, 255, 0.70), dark: (255, 255, 255, 0.06))
    static let btn2Ring = adaptive(light: (22, 21, 28, 0.06), dark: (255, 255, 255, 0.05))

    /// `--bg`.
    static let bg = LinearGradient(stops: [
        .init(color: adaptive(light: (0xF5, 0xF5, 0xF8, 1), dark: (0x25, 0x23, 0x2E, 1)), location: 0),
        .init(color: adaptive(light: (0xF5, 0xF5, 0xF8, 1), dark: (0x18, 0x17, 0x1D, 1)), location: 0.42),
        .init(color: adaptive(light: (0xF5, 0xF5, 0xF8, 1), dark: (0x11, 0x10, 0x14, 1)), location: 1),
    ], startPoint: .top, endPoint: .bottom)
    /// `--brand-fill`.
    static let brandFill = LinearGradient(colors: [
        adaptive(light: (0x55, 0x4D, 0x9F, 1), dark: (0x57, 0x52, 0x82, 1)),
        adaptive(light: (0x43, 0x3C, 0x8C, 1), dark: (0x42, 0x3E, 0x62, 1)),
    ], startPoint: .top, endPoint: .bottom)
    /// `--btn2-bg`.
    static let btn2Fill = LinearGradient(colors: [
        adaptive(light: (0xEF, 0xEE, 0xF3, 1), dark: (255, 255, 255, 0.10)),
        adaptive(light: (0xE5, 0xE4, 0xEB, 1), dark: (255, 255, 255, 0.07)),
    ], startPoint: .top, endPoint: .bottom)
    /// `--mbtn-bg`.
    static let mbtnFill = LinearGradient(colors: [
        adaptive(light: (0xFF, 0xFF, 0xFF, 1), dark: (255, 255, 255, 0.11)),
        adaptive(light: (0xF4, 0xF3, 0xF7, 1), dark: (255, 255, 255, 0.08)),
    ], startPoint: .top, endPoint: .bottom)

    typealias Channels = (Double, Double, Double, Double)

    private static func adaptive(light: Channels, dark: Channels) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
        #else
        Color(uiColor: UIColor { @Sendable traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: c.3)
        })
        #endif
    }
}

/// The layout's exact type, scaled with Dynamic Type (mirrors `layoutFont` in
/// the app).
private struct ShareFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: size >= 17 ? .body : (size >= 15 ? .subheadline : .footnote))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

private extension View {
    func shareFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ShareFont(size: size, weight: weight))
    }
}

#if os(iOS)
/// `.btn-primary` / `.btn-secondary`: 50 pt, full width, radius 14, 17 pt
/// semibold, pressed = brightness 0.96.
private struct ShareLargeButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .shareFont(17, .semibold)
            .foregroundStyle(primary ? ShareTheme.onBrand : ShareTheme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if primary {
                    shape
                        .fill(ShareTheme.brandFill)
                        .overlay {
                            shape.fill(ShareTheme.btnHighlight)
                                .mask(alignment: .top) { Rectangle().frame(height: 1) }
                        }
                        .shadow(color: ShareTheme.btnDrop, radius: 1, y: 1)
                } else {
                    shape
                        .fill(ShareTheme.btn2Fill)
                        .overlay {
                            shape.fill(ShareTheme.btn2Highlight)
                                .mask(alignment: .top) { Rectangle().frame(height: 1) }
                        }
                        .overlay { shape.strokeBorder(ShareTheme.btn2Ring, lineWidth: 1) }
                }
            }
            .contentShape(shape)
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}
#endif

#if os(macOS)
/// `.mbtn` / `.mbtn-primary`: 26 pt, radius 6, 13 pt medium, at least 76 wide.
private struct ShareMacButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .shareFont(13, .medium)
            .foregroundStyle(primary ? ShareTheme.onBrand : ShareTheme.text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .frame(minWidth: 76)
            .background {
                if primary {
                    shape
                        .fill(ShareTheme.brandFill)
                        .overlay {
                            shape.fill(ShareTheme.btnHighlight)
                                .mask(alignment: .top) { Rectangle().frame(height: 1) }
                        }
                        .shadow(color: ShareTheme.btnDrop, radius: 1, y: 1)
                } else {
                    shape
                        .fill(ShareTheme.mbtnFill)
                        .overlay { shape.strokeBorder(ShareTheme.mbtnBorder, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.04), radius: 0.5, y: 1)
                }
            }
            .contentShape(shape)
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}
#endif

#if DEBUG && os(iOS)
#Preview("PhoneShareExt light") {
    ShareCreateView(longURL: "https://example.com/page", onDone: {},
                    previewState: .success(shortURL: "https://s.example/x7Kp2", shortCode: "x7Kp2"))
        .preferredColorScheme(.light)
}

#Preview("PhoneShareExt dark") {
    ShareCreateView(longURL: "https://example.com/page", onDone: {},
                    previewState: .success(shortURL: "https://s.example/x7Kp2", shortCode: "x7Kp2"))
        .preferredColorScheme(.dark)
}
#endif
