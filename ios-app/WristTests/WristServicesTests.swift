import XCTest
import WristCore
@testable import WristKit

final class WristServicesTests: XCTestCase {
    private var suiteName = ""

    override func tearDown() {
        if !suiteName.isEmpty {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    private func makeServices() -> WristServices {
        suiteName = "wrist.tests.\(UUID().uuidString)"
        return WristServices(
            settings: AppGroupStore(defaults: UserDefaults(suiteName: suiteName)!),
            secrets: InMemorySecretStore(),
            persistence: InMemoryWearPersistence(),
            transport: FixtureTransport.sample(),
            notificationCenter: FakeNotificationCenter()
        )
    }

    func testFixturesAreConfigured() {
        let services = WristServices.fixtures()
        XCTAssertTrue(services.isConfigured)
        XCTAssertNotNil(services.makeStore())
        XCTAssertTrue(services.isFixture)
    }

    func testSaveAndResetConnection() throws {
        let services = makeServices()
        XCTAssertFalse(services.isConfigured)
        XCTAssertNil(services.makeStore())

        try services.saveConnection(serverURL: URL(string: "https://example.test")!, token: "abc")
        XCTAssertEqual(services.token(), "abc")
        XCTAssertEqual(services.serverURL.host(), "example.test")
        XCTAssertTrue(services.isConfigured)
        XCTAssertNotNil(services.makeStore())

        services.settings.nudgeConfig = NudgeConfig(enabled: true, hour: 6, minute: 30)
        services.resetConnection()
        XCTAssertFalse(services.isConfigured)
        XCTAssertNil(services.makeStore())
        XCTAssertEqual(services.settings.nudgeConfig, .default)
    }
}
