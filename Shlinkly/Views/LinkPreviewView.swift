//
//  LinkPreviewView.swift
//  Shlinkly
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A matte link preview for a URL: the site's icon, the page title and the
/// host, in the app's own palette. Metadata comes from `LinkPresentation`, but
/// nothing of the site's styling is drawn — no system link view, no site colors, no
/// hero image. Tapping opens the URL in the browser.
///
/// **Only ever pass the destination (long) URL here.** Fetching metadata makes
/// a real HTTP request to the URL; pointing it at a Shlink short URL would
/// follow the redirect and record a visit — inflating the very statistics this
/// screen displays. For the same reason the tap opens this URL, never the
/// short one.
struct LinkPreviewView: View {
    let url: URL

    @State private var phase: LinkPreviewCache.Phase = .loading
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            row
        }
        .buttonStyle(.plain)
        .help("Open in browser")
        .accessibilityLabel("Open \(accessibilityTitle)")
        .accessibilityValue(host)
        .task(id: url) {
            phase = await LinkPreviewCache.preview(for: url)
        }
    }

    /// The preview row as drawn: the site icon on a `--npastel` tile, the page
    /// title (medium) over the host (`--text2`), and "↗". Mac: 52 pt tall, a
    /// 28 pt tile (radius 7), 13 / 11 pt, 14 pt in. iPhone: at least 56 pt, a
    /// 30 pt tile (radius 8), 15 / 13 pt, 16 pt in.
    private var row: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .layoutFont(Metrics.titleSize, .medium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .redacted(reason: phase == .loading ? .placeholder : [])
                Text(host)
                    .layoutFont(Metrics.hostSize)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("↗")
                .layoutFont(Metrics.titleSize)
                .foregroundStyle(Palette.text2)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.inset)
        .frame(minHeight: Metrics.height)
        .contentShape(Rectangle())
    }

    private enum Metrics {
        #if os(macOS)
        static let height: CGFloat = 52
        static let tile: CGFloat = 28
        static let tileRadius: CGFloat = 7
        static let glyph: CGFloat = 13
        static let titleSize: CGFloat = 13
        static let hostSize: CGFloat = 11
        static let inset: CGFloat = 14
        #else
        static let height: CGFloat = 56
        static let tile: CGFloat = 30
        static let tileRadius: CGFloat = 8
        static let glyph: CGFloat = 14
        static let titleSize: CGFloat = 15
        static let hostSize: CGFloat = 13
        static let inset: CGFloat = 16
        #endif
    }

    /// The site icon on the `--npastel` tile; a globe in `--text2` when there is
    /// none (or while it loads), a link symbol for the plain-link fallback.
    private var icon: some View {
        RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
            .fill(Palette.npastel)
            .frame(width: Metrics.tile, height: Metrics.tile)
            .overlay {
                if case .loaded(_, let image?) = phase {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: Metrics.tile - 10, height: Metrics.tile - 10)
                } else {
                    Image(systemName: phase == .failed ? "link" : "globe")
                        .font(.system(size: Metrics.glyph))
                        .foregroundStyle(Palette.text2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The page title; the full URL for the plain-link fallback (no metadata).
    private var title: String {
        switch phase {
        case .loading: return "Loading the page title"
        case .loaded(let title?, _): return title
        case .loaded(nil, _): return host
        case .failed: return url.absoluteString
        }
    }

    private var accessibilityTitle: String {
        if case .loaded(let title?, _) = phase { return title }
        return host
    }

    /// The URL's host without a leading "www.".
    private var host: String {
        let raw = url.host() ?? url.absoluteString
        return raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
    }
}

// MARK: - Metadata cache

/// Fetched link metadata, kept for the session so returning to a link (or
/// switching between links on the Mac) doesn't refetch it. Failures are kept
/// too, so an unreachable site isn't retried on every appearance.
@MainActor
enum LinkPreviewCache {
    enum Phase: Equatable {
        case loading
        /// The page title (if the site has one) and its icon (if it has one).
        case loaded(title: String?, icon: Image?)
        /// No metadata: offline, blocked, or not a web page.
        case failed

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed): return true
            case let (.loaded(lhsTitle, lhsIcon), .loaded(rhsTitle, rhsIcon)):
                return lhsTitle == rhsTitle && (lhsIcon == nil) == (rhsIcon == nil)
            default: return false
            }
        }
    }

    private static var entries: [URL: Phase] = [:]

    static func preview(for url: URL) async -> Phase {
        if let cached = entries[url] { return cached }
        let fetched = await fetch(url)
        // A cancelled fetch (the view went away) isn't an answer; don't keep it.
        if !Task.isCancelled { entries[url] = fetched }
        return fetched
    }

    private static func fetch(_ url: URL) async -> Phase {
        #if DEBUG
        // Demo mode (Debug only): the dataset's title, no icon, no request.
        if DemoMode.isOn {
            return .loaded(title: DemoMode.previewTitle(for: url), icon: nil)
        }
        #endif
        do {
            // A fresh provider per fetch: each instance is single-use.
            let provider = LPMetadataProvider()
            let metadata = try await provider.startFetchingMetadata(for: url)
            let title = metadata.title.flatMap { $0.isEmpty ? nil : $0 }
            var icon: Image?
            if let iconProvider = metadata.iconProvider {
                icon = await loadImage(from: iconProvider)
            }
            return .loaded(title: title, icon: icon)
        } catch {
            return .failed
        }
    }

    /// Loads the icon's image data and turns it into a SwiftUI image.
    private static func loadImage(from provider: NSItemProvider) async -> Image? {
        let data: Data? = await withCheckedContinuation { continuation in
            // `@Sendable`: the provider calls back on a background queue, so the
            // closure must not inherit the main actor.
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        #if os(macOS)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}
