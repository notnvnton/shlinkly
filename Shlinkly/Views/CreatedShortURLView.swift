//
//  CreatedShortURLView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The focused success screen shown after a link is *created* (not edited): the
/// new short URL large and centred, a "Copied" confirmation (it's already on the
/// clipboard), a system share button, and Done to return to the list — where the
/// new link is already at the top.
struct CreatedShortURLView: View {
    let shortURL: ShortURL
    let onDone: () -> Void

    /// The short URL with the scheme stripped, for display.
    private var displayURL: String {
        shortURL.shortUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Link created")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(displayURL)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal)

                    Label("Copied to clipboard", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if let url = URL(string: shortURL.shortUrl) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 40)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 420)
            #endif
        }
    }
}
