//
//  QRCodeRenderer.swift
//  Shlinkly
//

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import ImageIO
import UniformTypeIdentifiers
import ShlinklyCore

/// The Core Image half of the QR code feature: the module matrix for a short
/// URL, and the PNG drawn from it. Made on the device; Shlink's own QR
/// endpoint (deprecated since Shlink 4.5.0) is never called. The SVG is
/// ``QRCodeSVG`` in ``ShlinklyCore``.
nonisolated enum QRCodeRenderer {
    /// The module matrix for `message` (the full short URL, as UTF-8), at
    /// correction level M.
    ///
    /// How the grid comes out of Core Image: `CIQRCodeGenerator` draws one
    /// pixel per module, black (0) on white (255), and adds a white margin of
    /// its own (1 module with the current SDK). The image is rendered to an
    /// 8-bit gray bitmap, top row first, and the margin is cut away by taking
    /// the bounding box of the dark pixels: the three finder patterns sit in
    /// the code's top-left, top-right and bottom-left corners, so that box is
    /// exactly the code, whatever margin Core Image adds. A pixel darker than
    /// 128 is a dark module. The result must be a square of 21 + 4k modules (a
    /// QR version), or there's no code.
    static func matrix(for message: String) -> QRModuleMatrix? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height)
        CIContext(options: [.cacheIntermediates: false])
            .render(image, toBitmap: &pixels, rowBytes: width, bounds: extent, format: .L8, colorSpace: nil)

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let side = maxX - minX + 1
        guard maxX >= 0, side == maxY - minY + 1, side >= 21, (side - 21) % 4 == 0 else { return nil }

        let rows = (minY...maxY).map { y in
            (minX...maxX).map { x in pixels[y * width + x] < 128 }
        }
        return QRModuleMatrix(rows: rows)
    }

    /// The PNG: 1024 × 1024 px, white, the modules in `color` as whole-pixel
    /// squares (every module the same size, no smoothing), centered with at
    /// least 4 modules of white around them (``QRRasterLayout``).
    static func pngData(for matrix: QRModuleMatrix, color: QRCodeColor,
                        pixelSize: Int = QRCodeExportSpec.pngPixelSize) -> Data? {
        guard let layout = QRRasterLayout(moduleCount: matrix.size, pixelSize: pixelSize),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

        let rgb = color.rgb
        context.setFillColor(CGColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                                     blue: CGFloat(rgb.blue) / 255, alpha: 1))
        let step = layout.modulePixels
        for run in matrix.runs {
            // Core Graphics counts rows from the bottom.
            let top = layout.origin + run.y * step
            context.fill(CGRect(x: layout.origin + run.x * step, y: pixelSize - top - step,
                                width: run.length * step, height: step))
        }

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// One QR code, ready to leave the app: the PNG and the SVG in one color, and
/// the format the user picked. Shared through `ShareLink`, dragged to Finder
/// (Mac) and copied, always as `<shortCode>-qr.<ext>`.
nonisolated struct QRCodeExport: Transferable, Sendable {
    let shortCode: String
    let format: QRCodeFormat
    let png: Data
    let svg: Data

    var fileName: String { QRCodeExportSpec.fileName(shortCode: shortCode, format: format) }

    /// The chosen format's bytes.
    var data: Data { format == .png ? png : svg }

    /// The chosen file, written to its own folder in the temporary directory
    /// so it carries its exact name.
    func writeFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("QRCode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { export in
            SentTransferredFile(try export.writeFile())
        }
        .exportingCondition { $0.format == .png }
        .suggestedFileName { $0.fileName }
        FileRepresentation(exportedContentType: .svg) { export in
            SentTransferredFile(try export.writeFile())
        }
        .exportingCondition { $0.format == .svg }
        .suggestedFileName { $0.fileName }
    }
}
