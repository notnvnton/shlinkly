//
//  QRCode.swift
//  ShlinklyCore
//

import Foundation

// The pure half of the QR code feature (layout v3, `PhoneQR` / `MacQRSheet`):
// the colors, the formats, the file names, the PNG raster layout and the SVG
// document. Generating the module matrix needs Core Image and lives in the app
// (`QRCodeRenderer`); everything here works on a plain `[[Bool]]`.

/// A QR code's module grid: `rows[y][x]` is `true` for a dark module. Always
/// square and never empty. The quiet zone is *not* part of it.
public struct QRModuleMatrix: Equatable, Sendable {
    public let rows: [[Bool]]

    /// `nil` unless `rows` is a non-empty square.
    public init?(rows: [[Bool]]) {
        guard !rows.isEmpty, rows.allSatisfy({ $0.count == rows.count }) else { return nil }
        self.rows = rows
    }

    /// Modules per side.
    public var size: Int { rows.count }

    public subscript(x: Int, y: Int) -> Bool { rows[y][x] }

    /// A horizontal run of dark modules: `length` modules from (`x`, `y`).
    public struct Run: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let length: Int
    }

    /// Every row's runs of dark modules, top to bottom, left to right. The SVG
    /// path, the PNG and the on-screen code are all drawn from these.
    public var runs: [Run] {
        var result: [Run] = []
        for y in 0..<size {
            var x = 0
            while x < size {
                guard rows[y][x] else { x += 1; continue }
                var length = 1
                while x + length < size, rows[y][x + length] { length += 1 }
                result.append(Run(x: x, y: y, length: length))
                x += length
            }
        }
        return result
    }
}

/// The three foreground colors. The background is always white, in light and
/// dark mode alike.
public enum QRCodeColor: String, CaseIterable, Identifiable, Sendable {
    case brand
    case graphite
    case black

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .brand: return "Brand"
        case .graphite: return "Graphite"
        case .black: return "Black"
        }
    }

    /// `#RRGGBB`, upper case.
    public var hex: String {
        switch self {
        case .brand: return "#433C8C"
        case .graphite: return "#2E2D36"
        case .black: return "#000000"
        }
    }

    /// 0–255 sRGB channels.
    public var rgb: (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .brand: return (0x43, 0x3C, 0x8C)
        case .graphite: return (0x2E, 0x2D, 0x36)
        case .black: return (0, 0, 0)
        }
    }
}

/// The export formats of the Format control.
public enum QRCodeFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case svg

    public var id: String { rawValue }

    /// "PNG" / "SVG".
    public var label: String { rawValue.uppercased() }

    public var fileExtension: String { rawValue }
}

public enum QRCodeExportSpec {
    /// White modules around the code in every exported file.
    public static let quietZone = 4
    /// The PNG's width and height, quiet zone included.
    public static let pngPixelSize = 1024

    /// `<shortCode>-qr.png` / `<shortCode>-qr.svg`. A multi-segment slug's `/`
    /// (and any other character a file name can't hold) becomes `-`.
    public static func fileName(shortCode: String, format: QRCodeFormat) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:")
        let safe = shortCode.unicodeScalars
            .map { unsafe.contains($0) ? "-" : String($0) }
            .joined()
        return "\(safe.isEmpty ? "link" : safe)-qr.\(format.fileExtension)"
    }
}

/// Where the modules go in a square raster: every module the same whole number
/// of pixels, centered, with at least `minQuietZone` modules of white around
/// it. Pixels that don't divide evenly widen the quiet zone (the extra is
/// split, the odd pixel going to the right and bottom).
public struct QRRasterLayout: Equatable, Sendable {
    /// Pixels per module.
    public let modulePixels: Int
    /// The left and top edge of the first module, in pixels.
    public let origin: Int
    /// The raster's width and height.
    public let pixelSize: Int

    public init?(moduleCount: Int, pixelSize: Int, minQuietZone: Int = QRCodeExportSpec.quietZone) {
        let span = moduleCount + 2 * minQuietZone
        guard moduleCount > 0, minQuietZone >= 0, pixelSize >= span else { return nil }
        let modulePixels = pixelSize / span
        let leftover = pixelSize - modulePixels * span
        self.modulePixels = modulePixels
        self.origin = minQuietZone * modulePixels + leftover / 2
        self.pixelSize = pixelSize
    }
}

public enum QRCodeSVG {
    /// The SVG file for `matrix`: a white background `<rect>`, then the dark
    /// modules as one `<path>` filled with `color` (each row's runs of dark
    /// modules merged into one rectangle). `viewBox` is in modules, quiet zone
    /// included; `shape-rendering="crispEdges"` keeps the module edges sharp.
    public static func document(for matrix: QRModuleMatrix, color: QRCodeColor,
                                quietZone: Int = QRCodeExportSpec.quietZone) -> String {
        let side = matrix.size + 2 * quietZone
        let path = matrix.runs
            .map { "M\($0.x + quietZone) \($0.y + quietZone)h\($0.length)v1h-\($0.length)z" }
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(side) \(side)" shape-rendering="crispEdges">\
        <rect width="\(side)" height="\(side)" fill="#FFFFFF"/>\
        <path fill="\(color.hex)" d="\(path)"/>\
        </svg>

        """
    }
}
