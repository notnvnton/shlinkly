import Foundation
import Testing
@testable import ShlinklyCore

struct QRCodeTests {
    /// A real version-1 code (21 × 21, level M) for "Shlinkly", as Core Image
    /// draws it, with Core Image's 1-module margin removed.
    static let version1: [String] = [
        "#######..##...#######",
        "#.....#....#..#.....#",
        "#.###.#.#...#.#.###.#",
        "#.###.#.#####.#.###.#",
        "#.###.#.#.###.#.###.#",
        "#.....#.#...#.#.....#",
        "#######.#.#.#.#######",
        "........#####........",
        "#.#####..##.#.#####..",
        ".###.#..###.#.#.#...#",
        "#.....#.####.#....##.",
        "###....####....#.####",
        ".#.#.###.###....#....",
        "........#..#######.#.",
        "#######..##.#.#...##.",
        "#.....#.#..####.###..",
        "#.###.#.###.#..##...#",
        "#.###.#.##..#..##....",
        "#.###.#.#..#.#...##..",
        "#.....#..##....####..",
        "#######.#.##.#..#..#.",
    ]

    static func matrix(_ rows: [String]) throws -> QRModuleMatrix {
        try #require(QRModuleMatrix(rows: rows.map { $0.map { $0 == "#" } }))
    }

    /// Every `M{x} {y}h{n}v1h-{n}z` rectangle of a path, as (x, y, n).
    static func runs(in svg: String) throws -> [(x: Int, y: Int, n: Int)] {
        let d = try #require(svg.firstMatch(of: /d="([^"]*)"/)).1
        return d.matches(of: /M(\d+) (\d+)h(\d+)v1h-(\d+)z/).map {
            (Int($0.1)!, Int($0.2)!, Int($0.3)!)
        }
    }

    // MARK: SVG

    @Test("One dark module: white rect, one path, the quiet zone in the viewBox")
    func singleModule() throws {
        let svg = QRCodeSVG.document(for: try Self.matrix(["#"]), color: .black)
        #expect(svg == """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 9 9" shape-rendering="crispEdges">\
        <rect width="9" height="9" fill="#FFFFFF"/><path fill="#000000" d="M4 4h1v1h-1z"/></svg>

        """)
    }

    @Test("Runs of dark modules in a row merge into one rectangle")
    func mergesRuns() throws {
        let svg = QRCodeSVG.document(for: try Self.matrix(["##", ".#"]), color: .graphite)
        #expect(svg.contains(##"d="M4 4h2v1h-2zM5 5h1v1h-1z""##))
        #expect(svg.contains(##"viewBox="0 0 10 10""##))
    }

    @Test("A 21 × 21 code: 29-module viewBox, finder row offset by the quiet zone")
    func version1Document() throws {
        let matrix = try Self.matrix(Self.version1)
        let svg = QRCodeSVG.document(for: matrix, color: .brand)
        #expect(svg.contains(##"viewBox="0 0 29 29""##))
        #expect(svg.contains(##"<rect width="29" height="29" fill="#FFFFFF"/>"##))
        #expect(svg.contains(##"shape-rendering="crispEdges""##))
        #expect(svg.contains(##"d="M4 4h7v1h-7zM13 4h2v1h-2zM18 4h7v1h-7z"##))
        // Exactly one path, in the chosen color.
        #expect(svg.matches(of: #/<path /#).count == 1)
        #expect(svg.contains(##"<path fill="#433C8C""##))
    }

    @Test("The path covers exactly the dark modules, all inside the quiet zone")
    func version1Coverage() throws {
        let matrix = try Self.matrix(Self.version1)
        let runs = try Self.runs(in: QRCodeSVG.document(for: matrix, color: .brand))
        var covered = Set<[Int]>()
        for run in runs {
            #expect(run.x >= 4 && run.y >= 4 && run.x + run.n <= 25 && run.y < 25)
            for x in run.x..<(run.x + run.n) { covered.insert([x - 4, run.y - 4]) }
        }
        var dark = Set<[Int]>()
        for y in 0..<21 { for x in 0..<21 where matrix[x, y] { dark.insert([x, y]) } }
        #expect(covered == dark)
        #expect(runs.reduce(0) { $0 + $1.n } == dark.count)
    }

    @Test("A custom quiet zone moves the modules and grows the viewBox")
    func customQuietZone() throws {
        let svg = QRCodeSVG.document(for: try Self.matrix(["#"]), color: .black, quietZone: 2)
        #expect(svg.contains(##"viewBox="0 0 5 5""##))
        #expect(svg.contains(##"d="M2 2h1v1h-1z""##))
    }

    @Test("Each color writes its hex")
    func colors() throws {
        let matrix = try Self.matrix(["#"])
        #expect(QRCodeSVG.document(for: matrix, color: .brand).contains(##"fill="#433C8C""##))
        #expect(QRCodeSVG.document(for: matrix, color: .graphite).contains(##"fill="#2E2D36""##))
        #expect(QRCodeSVG.document(for: matrix, color: .black).contains(##"fill="#000000""##))
    }

    // MARK: Matrix

    @Test("Only a non-empty square is a matrix")
    func matrixValidation() {
        #expect(QRModuleMatrix(rows: []) == nil)
        #expect(QRModuleMatrix(rows: [[true, false]]) == nil)
        #expect(QRModuleMatrix(rows: [[true], [false, true]]) == nil)
        #expect(QRModuleMatrix(rows: [[true, false], [false, true]])?.size == 2)
    }

    // MARK: PNG layout

    @Test("25 modules in 1024 px: uniform 31 px modules, at least 4 quiet modules")
    func rasterVersion2() throws {
        let layout = try #require(QRRasterLayout(moduleCount: 25, pixelSize: 1024))
        #expect(layout.modulePixels == 31)
        #expect(layout.origin == 124)
        let trailing = 1024 - (layout.origin + 25 * layout.modulePixels)
        #expect(trailing == 125)
        #expect(layout.origin >= 4 * 31 && trailing >= 4 * 31)
    }

    @Test("Leftover pixels are split around the code")
    func rasterVersion1() throws {
        let layout = try #require(QRRasterLayout(moduleCount: 21, pixelSize: 1024))
        #expect(layout.modulePixels == 35)
        #expect(layout.origin == 144)
        #expect(1024 - (layout.origin + 21 * 35) == 145)
    }

    @Test("A raster too small for the code and its quiet zone is refused")
    func rasterTooSmall() {
        #expect(QRRasterLayout(moduleCount: 25, pixelSize: 32) == nil)
        #expect(QRRasterLayout(moduleCount: 0, pixelSize: 1024) == nil)
    }

    // MARK: File names

    @Test("File names are <shortCode>-qr.<ext>")
    func fileNames() {
        #expect(QRCodeExportSpec.fileName(shortCode: "ajJCw", format: .png) == "ajJCw-qr.png")
        #expect(QRCodeExportSpec.fileName(shortCode: "ajJCw", format: .svg) == "ajJCw-qr.svg")
        #expect(QRCodeExportSpec.fileName(shortCode: "blog/launch", format: .png) == "blog-launch-qr.png")
    }
}
