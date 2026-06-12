//
//  LinkPreviewView.swift
//  Shlinkly
//

import SwiftUI
import LinkPresentation

/// A native rich link preview for a URL, backed by `LinkPresentation`.
///
/// **Only ever pass the destination (long) URL here.** Fetching metadata makes
/// a real HTTP request to the URL; pointing it at a Shlink short URL would
/// follow the redirect and record a visit — inflating the very statistics this
/// screen displays.
struct LinkPreviewView: View {
    let url: URL

    @State private var metadata: LPLinkMetadata?
    @State private var failed = false

    var body: some View {
        Group {
            if let metadata {
                LinkMetadataView(metadata: metadata)
            } else if failed {
                fallback
            } else {
                placeholder
            }
        }
        .task(id: url) {
            metadata = nil
            failed = false
            do {
                // A fresh provider per fetch: each instance is single-use.
                let provider = LPMetadataProvider()
                metadata = try await provider.startFetchingMetadata(for: url)
            } catch {
                failed = true
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.06))
            .frame(height: 84)
            .overlay { ProgressView() }
            .accessibilityLabel("Loading link preview")
    }

    /// Shown when metadata can't be fetched (offline, blocked, no Open Graph
    /// data): a plain link affordance rather than an empty gap.
    private var fallback: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LPLinkView bridge

#if os(macOS)
import AppKit

private struct LinkMetadataView: NSViewRepresentable {
    let metadata: LPLinkMetadata

    func makeNSView(context: Context) -> LPLinkView {
        LPLinkView(metadata: metadata)
    }

    func updateNSView(_ view: LPLinkView, context: Context) {
        view.metadata = metadata
    }
}
#else
import UIKit

private struct LinkMetadataView: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        LPLinkView(metadata: metadata)
    }

    func updateUIView(_ view: LPLinkView, context: Context) {
        view.metadata = metadata
    }
}
#endif
