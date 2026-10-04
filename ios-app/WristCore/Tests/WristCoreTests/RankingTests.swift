import XCTest
@testable import WristCore

final class RankingTests: XCTestCase {
    private func watch(_ id: String, _ brand: String, _ model: String) -> WearWatch {
        WearWatch(id: id, brand: brand, model: model, imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "https://bsky.app/profile/ryanswatches.com/post/\(id)",
                  wearCount: 0, lastWornAt: nil, postCount: 1)
    }

    func testTopWatchesLimitsAndExcludes() {
        XCTAssertEqual(Ranking.topWatches(Fixtures.watches, limit: 2).map(\.id), ["3m2uvdvq7622g", "3mwz3ctxxnc26"])
        XCTAssertEqual(Ranking.topWatches(Fixtures.watches, limit: 2, excluding: "3m2uvdvq7622g").map(\.id),
                       ["3mwz3ctxxnc26", "3m2uxrekinc2e"])
        XCTAssertEqual(Ranking.topWatches(Fixtures.watches, limit: 10).count, 3)
        XCTAssertTrue(Ranking.topWatches(Fixtures.watches, limit: 0).isEmpty)
    }

    func testShortLabel() {
        XCTAssertEqual(Ranking.shortLabel(for: Fixtures.kurono), "Kurono Malachite")
        let truncated = Ranking.shortLabel(for: Fixtures.citizen)
        XCTAssertEqual(truncated.count, 18)
        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertEqual(truncated, "Citizen Eco Drive…")
    }

    func testShortLabelNeverEmpty() {
        XCTAssertFalse(Ranking.shortLabel(for: watch("x", "", "")).isEmpty)
    }

    func testCollisionsUseInitialForm() {
        let a = watch("a", "Omega", "Speedmaster Professional")
        let b = watch("b", "Omega", "Speedmaster Moonwatch")
        XCTAssertEqual(Ranking.shortLabel(for: a), Ranking.shortLabel(for: b))
        let labels = Ranking.shortLabels(for: [a, b, Fixtures.kurono])
        XCTAssertEqual(Set(labels).count, 3)
        XCTAssertTrue(labels[0].hasPrefix("O. "))
        XCTAssertTrue(labels[1].hasPrefix("O. "))
        XCTAssertEqual(labels[2], "Kurono Malachite")
    }

    func testIdenticalWatchesGetNumericSuffixes() {
        let w = [watch("a", "Seiko", "5"), watch("b", "Seiko", "5"), watch("c", "Seiko", "5")]
        XCTAssertEqual(Ranking.shortLabels(for: w), ["S. 5", "S. 5 (2)", "S. 5 (3)"])
    }

    func testFixtureLabelsMatchIndividual() {
        XCTAssertEqual(Ranking.shortLabels(for: Fixtures.watches), Fixtures.watches.map { Ranking.shortLabel(for: $0) })
    }
}
