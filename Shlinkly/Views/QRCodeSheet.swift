//
//  QRCodeSheet.swift
//  Shlinkly
//

import SwiftUI
import ShlinklyCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A link's QR code, as layout v3 draws it: `PhoneQR` (a sheet over the
/// iPhone detail) and `MacQRSheet` (a 420 pt sheet over the Mac window). The
/// code is made on this device (``QRCodeRenderer``); Color and Format start at
/// Brand and PNG on every open and aren't saved.
struct QRCodeSheet: View {
    @State private var document: QRCodeDocument
    @State private var color: QRCodeColor = .brand
    @State private var format: QRCodeFormat = .png
    /// Drives the copy button's brief "Copied".
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(shortURL: ShortURL) {
        _document = State(initialValue: QRCodeDocument(shortURL: shortURL))
    }

    private var export: QRCodeExport? { document.export(color: color, format: format) }

    var body: some View {
        #if os(macOS)
        macSheet
        #else
        phoneSheet
        #endif
    }

    /// Puts the PNG (and on the Mac, with SVG chosen, the SVG too) on the
    /// pasteboard and reads "Copied" for 1.5 s.
    private func copyImage() {
        guard let export else { return }
        #if os(macOS)
        Clipboard.copyImage(png: export.png, svg: format == .svg ? export.svg : nil)
        #else
        Clipboard.copyImage(png: export.png)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    /// "Copy image" / "Copy Image" and "Copied" in the same space, so the
    /// button never changes size.
    private func copyLabel(_ title: String) -> some View {
        ZStack {
            Text(title).opacity(didCopy ? 0 : 1)
            Text("Copied").opacity(didCopy ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(didCopy ? "Copied" : title)
    }

    /// The code itself, `margin` modules of white around it, as the artboards
    /// draw it inside the white card (the exported files have 4).
    @ViewBuilder
    private func code(side: CGFloat) -> some View {
        if let matrix = document.matrix {
            QRCodeGlyph(matrix: matrix, color: color, margin: 2)
                .frame(width: side, height: side)
                .accessibilityLabel("QR code for \(document.displayURL)")
        } else {
            Color.clear
                .frame(width: side, height: side)
                .accessibilityLabel("No QR code")
        }
    }

    /// The white card behind the code: `#FFFFFF` with a 1 pt `#E4E4EA` ring
    /// in light and dark mode alike.
    private func whiteCard(size: CGFloat, radius: CGFloat, padding: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return code(side: size - 2 * padding)
            .padding(padding)
            .frame(width: size, height: size)
            .background(Color(.sRGB, red: 1, green: 1, blue: 1), in: shape)
            .overlay(shape.strokeBorder(Color(hex(0xE4E4EA)), lineWidth: 1))
    }

    private var footnote: String {
        #if os(macOS)
        "Made on this device. Drag the code to Finder to save it. Every scan counts as a visit."
        #else
        "Made on this device. Every scan opens the short link and counts as a visit."
        #endif
    }

    private var preview: SharePreview<Image, Never> {
        SharePreview(export?.fileName ?? "QR code", image: previewImage)
    }

    private var previewImage: Image {
        #if os(macOS)
        if let png = export?.png, let image = NSImage(data: png) { return Image(nsImage: image) }
        #else
        if let png = export?.png, let image = UIImage(data: png) { return Image(uiImage: image) }
        #endif
        return Image(systemName: "qrcode")
    }

    #if os(iOS)
    // MARK: - iPhone (PhoneQR)

    private var phoneSheet: some View {
        VStack(spacing: 0) {
            SheetHeader("QR code") {
                Button("Done") { dismiss() }
                    .buttonStyle(.navLink(.semibold))
            }
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        whiteCard(size: 248, radius: 18, padding: 20)
                        Text(document.displayURL)
                            .layoutFont(16, .medium)
                            .foregroundStyle(Palette.brand)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 16)
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel("Color")
                            LayoutCard {
                                HStack(spacing: 10) {
                                    ForEach(QRCodeColor.allCases) { choice in
                                        PhoneColorChoice(color: choice, isSelected: choice == color) {
                                            color = choice
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("QR color")
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel("Format")
                            Picker("Format", selection: $format) {
                                ForEach(QRCodeFormat.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Footnote(footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                Button(action: copyImage) {
                    copyLabel("Copy image")
                }
                .buttonStyle(.layoutSecondary)
                .disabled(export == nil)
                if let export {
                    ShareLink(item: export, preview: preview) {
                        Text("Share")
                    }
                    .buttonStyle(.layoutPrimary)
                } else {
                    Button("Share") {}
                        .buttonStyle(.layoutPrimary)
                        .disabled(true)
                }
            }
        }
        .canvasBackground()
    }
    #endif

    #if os(macOS)
    // MARK: - Mac (MacQRSheet)

    private var macSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QR code")
                .layoutFont(15, .semibold)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 10) {
                draggableCode
                Text(document.displayURL)
                    .layoutFont(13, .medium)
                    .foregroundStyle(Palette.brand)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            VStack(alignment: .leading, spacing: 0) {
                MacCard(solid: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            FieldLabel("Color")
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                ForEach(QRCodeColor.allCases) { choice in
                                    MacColorSwatch(color: choice, isSelected: choice == color) {
                                        color = choice
                                    }
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("QR color")
                        }
                        .macField(height: 40)
                        RowSeparator()
                        HStack(spacing: 12) {
                            FieldLabel("Format")
                            Spacer(minLength: 0)
                            MacSegmented("Format", selection: $format,
                                         options: QRCodeFormat.allCases.map { .init(value: $0, label: $0.label) },
                                         size: .small)
                        }
                        .macField(height: 40)
                    }
                }
                // `.foot` keeps its 8 pt top padding here (the Mac's
                // ``Footnote`` has 6).
                Footnote(footnote)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            HStack(spacing: 8) {
                Button(action: copyImage) {
                    copyLabel("Copy Image")
                }
                .buttonStyle(.mac)
                .disabled(export == nil)
                if let export {
                    ShareLink(item: export, preview: preview) {
                        Text("Share…")
                    }
                    .buttonStyle(.mac)
                } else {
                    Button("Share…") {}
                        .buttonStyle(.mac)
                        .disabled(true)
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { RowSeparator() }
            .padding(.top, 14)
        }
        .frame(width: 420)
        .background(Palette.sheetBg)
        .onExitCommand { dismiss() }
    }

    /// The white card, 220 pt with 18 pt padding. Dragging it to Finder drops
    /// the chosen file.
    @ViewBuilder
    private var draggableCode: some View {
        let card = whiteCard(size: 220, radius: 14, padding: 18)
            .help("Drag to Finder to save")
        if let export {
            card.draggable(export)
        } else {
            card
        }
    }
    #endif
}

/// The modules of a code as one filled path (no seams between rows), with
/// `margin` modules of space around them, scaled to the view.
struct QRCodeGlyph: View {
    let matrix: QRModuleMatrix
    let color: QRCodeColor
    var margin: Int = 0

    var body: some View {
        Canvas { context, size in
            let module = min(size.width, size.height) / CGFloat(matrix.size + 2 * margin)
            var path = Path()
            for run in matrix.runs {
                path.addRect(CGRect(x: CGFloat(run.x + margin) * module, y: CGFloat(run.y + margin) * module,
                                    width: CGFloat(run.length) * module, height: module))
            }
            context.fill(path, with: .color(Color(qr: color)))
        }
    }
}

/// The code for one short URL: its matrix, made once per open, and the PNG
/// for each color as it's first asked for.
final class QRCodeDocument {
    let shortURL: ShortURL
    let matrix: QRModuleMatrix?
    private var pngs: [QRCodeColor: Data] = [:]

    init(shortURL: ShortURL) {
        self.shortURL = shortURL
        self.matrix = QRCodeRenderer.matrix(for: shortURL.shortUrl)
    }

    /// The short URL without its scheme, as the artboards show it.
    var displayURL: String {
        shortURL.shortUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    func export(color: QRCodeColor, format: QRCodeFormat) -> QRCodeExport? {
        guard let matrix else { return nil }
        let png: Data
        if let cached = pngs[color] {
            png = cached
        } else {
            guard let made = QRCodeRenderer.pngData(for: matrix, color: color) else { return nil }
            pngs[color] = made
            png = made
        }
        return QRCodeExport(shortCode: shortURL.shortCode, format: format, png: png,
                            svg: Data(QRCodeSVG.document(for: matrix, color: color).utf8))
    }
}

extension Color {
    /// A QR foreground color, the same in light and dark mode.
    init(qr color: QRCodeColor) {
        let rgb = color.rgb
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255,
                  blue: Double(rgb.blue) / 255)
    }
}

#if os(iOS)
/// One choice of the iPhone's Color card: a 24 pt swatch and the name in a
/// 36 pt capsule. The selected one sits on `--pastel` with a 1 pt
/// `--card-border` ring.
private struct PhoneColorChoice: View {
    let color: QRCodeColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(qr: color))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .frame(width: 24, height: 24)
                Text(color.label)
                    .layoutFont(14, .medium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 36)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Palette.pastel)
                        .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif

#if os(macOS)
/// One swatch of the Mac's Color row: a 24 pt circle. The selected one has a
/// 2 pt `--brand-text` ring with a 2 pt gap in the card's color; the others a
/// 1 pt inner ring of white at 25%.
private struct MacColorSwatch: View {
    let color: QRCodeColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(qr: color))
                .overlay {
                    if !isSelected {
                        Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    }
                }
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        // Outside the 24 pt circle, like the CSS box-shadow:
                        // the brand ring from 2 to 4 pt out, the gap inside it.
                        // The gap is the card as it looks (`--card` over the
                        // sheet), so it reads as space, not as a second ring.
                        ZStack {
                            Circle().fill(Palette.brand).frame(width: 32, height: 32)
                            Circle().fill(Palette.sheetBg).frame(width: 28, height: 28)
                            Circle().fill(Palette.card).frame(width: 28, height: 28)
                        }
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.label)
        .accessibilityLabel(color.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif

// MARK: - Preview

#if DEBUG
enum QRCodeSheetPreviewData {
    static let shortURL = ShortURL(
        shortCode: "ajJCw",
        shortUrl: "https://go.ahodge.de/ajJCw",
        longUrl: "https://library.ahodge.de/audiobookshelf/item/1",
        dateCreated: Date(),
        visitsSummary: VisitsSummary(total: 21, nonBots: 12, bots: 9),
        title: "Audiobookshelf",
        tags: ["books", "library"]
    )
}

#if os(macOS)
#Preview("MacQRSheet light") {
    QRCodeSheet(shortURL: QRCodeSheetPreviewData.shortURL)
        .brandTint()
        .preferredColorScheme(.light)
}

#Preview("MacQRSheet dark") {
    QRCodeSheet(shortURL: QRCodeSheetPreviewData.shortURL)
        .brandTint()
        .preferredColorScheme(.dark)
}
#else
#Preview("PhoneQR light") {
    QRCodeSheet(shortURL: QRCodeSheetPreviewData.shortURL)
        .brandTint()
        .preferredColorScheme(.light)
}

#Preview("PhoneQR dark") {
    QRCodeSheet(shortURL: QRCodeSheetPreviewData.shortURL)
        .brandTint()
        .preferredColorScheme(.dark)
}
#endif
#endif
