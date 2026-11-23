//
//  CreatedShortURLView.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore

/// The success screen shown after a link is *created* (not edited), as layout
/// v3 draws it (`PhoneCreated`): a `--brand-fill` card with "Link created", the
/// new short URL and "Copied to clipboard." (it already is), a card with where
/// it goes and its tags, then Share and Done. Done returns to the list, where
/// the new link is already at the top.
///
/// The Mac isn't drawn: it shows the same content in a sheet with `.mbtn`s.
struct CreatedShortURLView: View {
    let shortURL: ShortURL
    let onDone: () -> Void

    /// The short URL with the scheme stripped, for display.
    private var displayURL: String {
        shortURL.shortUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    /// The destination with the scheme stripped.
    private var displayDestination: String {
        shortURL.longUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        #if os(macOS)
        MacSheet("Link created") {
            hero
            MacCard(solid: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        FieldLabel("Goes to")
                        Text(displayDestination)
                            .foregroundStyle(Palette.text2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .macField()
                    if !shortURL.tags.isEmpty {
                        RowSeparator()
                        HStack(spacing: 6) {
                            FieldLabel("Tags")
                            Spacer(minLength: 8)
                            ForEach(shortURL.tags, id: \.self) { tag in
                                TagView(text: tag, size: .small)
                            }
                        }
                        .macField(height: 36)
                    }
                }
            }
        } bar: {
            Spacer(minLength: 8)
            if let url = URL(string: shortURL.shortUrl) {
                ShareLink(item: url) {
                    Text("Share")
                }
                .buttonStyle(.mac)
            }
            Button("Done", action: onDone)
                .buttonStyle(.macPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        #else
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    LayoutCard {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Goes to")
                                    .layoutFont(13)
                                    .foregroundStyle(Palette.text2)
                                Text(displayDestination)
                                    .layoutFont(15)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .layoutRow()
                            if !shortURL.tags.isEmpty {
                                RowSeparator()
                                HStack(spacing: 12) {
                                    Text("Tags")
                                        .layoutFont(13)
                                        .foregroundStyle(Palette.text2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    ForEach(shortURL.tags, id: \.self) { tag in
                                        TagView(text: tag)
                                    }
                                }
                                .layoutRow()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
            }
            BottomBar {
                if let url = URL(string: shortURL.shortUrl) {
                    ShareLink(item: url) {
                        Text("Share")
                    }
                    .buttonStyle(.layoutSecondary)
                }
                Button("Done", action: onDone)
                    .buttonStyle(.layoutPrimary)
            }
        }
        .canvasBackground()
        #endif
    }

    /// The brand card: a check, "Link created" (22 pt semibold), the short URL
    /// (17 pt medium) and "Copied to clipboard." (13 pt at 85%), in
    /// `--on-brand` on `--brand-fill`. Radius 16, 18 pt in (20 pt below), a
    /// 1 pt top highlight at 10%.
    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 20, weight: .medium))
                    .accessibilityHidden(true)
                Text("Link created")
                    .layoutFont(22, .semibold)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(displayURL)
                .layoutFont(17, .medium)
                .lineLimit(2)
                .textSelection(.enabled)
            Text("Copied to clipboard.")
                .layoutFont(13)
                .opacity(0.85)
        }
        .foregroundStyle(Palette.onBrand)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background {
            shape
                .fill(Palette.brandFill)
                .overlay {
                    shape
                        .fill(Color.white.opacity(0.10))
                        .mask(alignment: .top) { Rectangle().frame(height: 1) }
                }
        }
    }
}

#if DEBUG
private enum CreatedPreviewData {
    static let shortURL = ShortURL(
        shortCode: "spring-promo",
        shortUrl: "https://s.example/spring-promo",
        longUrl: "https://shop.example.com/spring?utm_source=newsletter",
        dateCreated: Date(),
        tags: ["campaign", "newsletter"]
    )
}

#if os(macOS)
#Preview("MacCreated light") {
    CreatedShortURLView(shortURL: CreatedPreviewData.shortURL) {}
        .brandTint()
        .preferredColorScheme(.light)
}

#Preview("MacCreated dark") {
    CreatedShortURLView(shortURL: CreatedPreviewData.shortURL) {}
        .brandTint()
        .preferredColorScheme(.dark)
}
#else
#Preview("PhoneCreated light") {
    CreatedShortURLView(shortURL: CreatedPreviewData.shortURL) {}
        .brandTint()
        .preferredColorScheme(.light)
}

#Preview("PhoneCreated dark") {
    CreatedShortURLView(shortURL: CreatedPreviewData.shortURL) {}
        .brandTint()
        .preferredColorScheme(.dark)
}
#endif
#endif
