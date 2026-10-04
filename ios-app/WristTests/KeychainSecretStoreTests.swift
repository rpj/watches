import XCTest
import WristCore
@testable import WristKit

final class KeychainSecretStoreTests: XCTestCase {
    private var service = ""
    private var store: KeychainSecretStore!
    private let keys = ["k1", "k2"]

    override func setUp() {
        super.setUp()
        service = "wrist.tests.\(UUID().uuidString)"
        store = KeychainSecretStore(service: service, accessGroup: nil)
    }

    override func tearDown() {
        for key in keys { try? store.delete(key) }
        store = nil
        super.tearDown()
    }

    func testSetGetRoundtrip() throws {
        try store.set("secret", for: "k1")
        XCTAssertEqual(try store.get("k1"), "secret")
    }

    func testOverwriteReturnsNewValue() throws {
        try store.set("one", for: "k1")
        try store.set("two", for: "k1")
        XCTAssertEqual(try store.get("k1"), "two")
    }

    func testDeleteThenGetIsNil() throws {
        try store.set("secret", for: "k1")
        try store.delete("k1")
        XCTAssertNil(try store.get("k1"))
    }

    func testDeleteMissingKeyDoesNotThrow() {
        XCTAssertNoThrow(try store.delete("k2"))
    }

    func testDifferentServicesAreIsolated() throws {
        let other = KeychainSecretStore(service: "wrist.tests.\(UUID().uuidString)", accessGroup: nil)
        defer { for key in keys { try? other.delete(key) } }
        try store.set("secret", for: "k1")
        XCTAssertNil(try other.get("k1"))
        try other.set("other", for: "k2")
        XCTAssertNil(try store.get("k2"))
    }
}
