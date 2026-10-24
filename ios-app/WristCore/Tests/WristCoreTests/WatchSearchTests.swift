import XCTest
@testable import WristCore

final class WatchSearchTests: XCTestCase {
    private func watch(_ id: String, _ brand: String, _ model: String) -> WearWatch {
        WearWatch(id: id, brand: brand, model: model, imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "https://bsky.app/profile/ryanswatches.com/post/\(id)",
                  wearCount: 0, lastWornAt: nil, postCount: 1)
    }

    private var watches: [WearWatch] {
        [
            watch("a", "Citizen", "Eco Drive 126900"),
            watch("b", "Kurono", "Malachite"),
            watch("c", "Seiko", "Éco Diver"),
            watch("d", "Omega", "Speedmaster"),
        ]
    }

    func testEmptyAndBlankQueryReturnInput() {
        XCTAssertEqual(WatchSearch.filter(watches, query: ""), watches)
        XCTAssertEqual(WatchSearch.filter(watches, query: "   \t "), watches)
    }

    func testPrefixMatch() {
        XCTAssertEqual(WatchSearch.filter(watches, query: "kur").map(\.id), ["b"])
    }

    func testCaseInsensitive() {
        XCTAssertEqual(WatchSearch.filter(watches, query: "KURONO").map(\.id), ["b"])
    }

    func testDiacriticInsensitive() {
        XCTAssertEqual(WatchSearch.filter(watches, query: "éco").map(\.id), ["a", "c"])
        XCTAssertEqual(WatchSearch.filter(watches, query: "eco").map(\.id), ["a", "c"])
    }

    func testMultiTokenRequiresAll() {
        XCTAssertEqual(WatchSearch.filter(watches, query: "eco 126900").map(\.id), ["a"])
        XCTAssertTrue(WatchSearch.filter(watches, query: "eco 999").isEmpty)
        XCTAssertTrue(WatchSearch.filter(watches, query: "kurono 126900").isEmpty)
    }

    func testBrandAndModelTokensCombine() {
        XCTAssertEqual(WatchSearch.filter(watches, query: "citizen drive").map(\.id), ["a"])
    }

    func testOrderPreserved() {
        let reversed = Array(watches.reversed())
        XCTAssertEqual(WatchSearch.filter(reversed, query: "eco").map(\.id), ["c", "a"])
    }

    func testNormalize() {
        XCTAssertEqual(WatchSearch.normalize("  Citizen   Eco "), "citizen eco")
    }
}
