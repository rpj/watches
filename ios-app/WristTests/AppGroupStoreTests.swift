import XCTest
import WristCore
@testable import WristKit

final class AppGroupStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "wrist.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testServerURLRoundtrip() {
        XCTAssertNil(store.serverURL)
        let url = URL(string: "https://example.test")!
        store.serverURL = url
        XCTAssertEqual(store.serverURL, url)
    }

    func testNudgeConfigDefaultsAndRoundtrip() {
        XCTAssertEqual(store.nudgeConfig, .default)
        let config = NudgeConfig(enabled: true, hour: 7, minute: 45)
        store.nudgeConfig = config
        XCTAssertEqual(store.nudgeConfig, config)
    }

    func testResetClearsBoth() {
        store.serverURL = URL(string: "https://example.test")!
        store.nudgeConfig = NudgeConfig(enabled: true, hour: 7, minute: 45)
        store.reset()
        XCTAssertNil(store.serverURL)
        XCTAssertEqual(store.nudgeConfig, .default)
    }
}
