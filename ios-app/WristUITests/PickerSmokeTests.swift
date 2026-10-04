import XCTest

final class PickerSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testTapFirstRowLogsAndUndoReverts() {
        let list = element("picker.list", preferred: app.collectionViews["picker.list"])
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let title = app.staticTexts["picker.currentTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Nothing logged yet")

        let row = app.descendants(matching: .any)["picker.row.3m2uvdvq7622g"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(waitForLabel(title, "Citizen Eco Drive E110-K16750", timeout: 5))

        let undo = element("picker.undo", preferred: app.buttons["picker.undo"])
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()

        XCTAssertTrue(waitForLabel(title, "Nothing logged yet", timeout: 5))
    }

    func testSettingsOpens() {
        let settings = element("picker.settings", preferred: app.buttons["picker.settings"])
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let toggle = element("settings.nudgeToggle", preferred: app.switches["settings.nudgeToggle"])
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// The preferred typed query if it appears shortly, else any element with the identifier.
    private func element(_ identifier: String, preferred: XCUIElement) -> XCUIElement {
        if preferred.firstMatch.waitForExistence(timeout: 3) { return preferred.firstMatch }
        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
