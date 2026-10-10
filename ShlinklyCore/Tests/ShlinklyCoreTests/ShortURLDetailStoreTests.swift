import Foundation
import Testing
@testable import ShlinklyCore

@Suite("Short URL detail store")
struct ShortURLDetailStoreTests {
    @Test("The Y ceiling is the nearest nice number at or above the peak", arguments: [
        (0, 1), (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6), (7, 8), (8, 8), (9, 10), (10, 10),
        (11, 15), (15, 15), (16, 20), (21, 25), (26, 30), (31, 40), (41, 50), (51, 60), (61, 80), (81, 100),
        (100, 100), (101, 150), (130, 150), (151, 200), (201, 250), (999, 1000), (1000, 1000), (1001, 1500),
        (12_345, 15_000),
    ])
    func niceCeiling(peak: Int, ceiling: Int) {
        #expect(ShortURLDetailStore.niceCeiling(peak) == ceiling)
    }

    @Test("The Y ceiling never cuts the peak off and never overshoots by more than half")
    func niceCeilingStaysTight() {
        for peak in 1...5_000 {
            let ceiling = ShortURLDetailStore.niceCeiling(peak)
            #expect(ceiling >= peak)
            // The widest gap in the ladder is 1 → 1.5, so the peak always
            // reaches at least two thirds of the axis.
            #expect(ceiling * 2 <= peak * 3 || peak < 10)
        }
    }
}
