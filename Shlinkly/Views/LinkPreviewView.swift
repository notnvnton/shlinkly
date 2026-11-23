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

    private var row: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .redacted(reason: phase == .loading ? .placeholder : [])
                Text(host)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.cardInset)
        .padding(.vertical, 12)
        .frame(minHeight: Space.rowTwo)
        .contentShape(Rectangle())
    }

    /// The site icon, 32×32 on a ``Palette/sunken`` tile; a globe when there is
    /// none (or while it loads), a link symbol for the plain-link fallback.
    private var icon: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Palette.sunken)
            .frame(width: 32, height: 32)
            .overlay {
                if case .loaded(_, let image?) = phase {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: phase == .failed ? "link" : "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
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
