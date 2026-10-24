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

    func testHoldFirstRowLogsAndUndoReverts() {
        let list = element("picker.list", preferred: app.collectionViews["picker.list"])
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let title = app.staticTexts["picker.currentTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Nothing logged yet")

        let row = app.descendants(matching: .any)["picker.row.3m2uvdvq7622g"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)

        XCTAssertTrue(waitForLabel(title, "Citizen Eco Drive E110-K16750", timeout: 5))

        let undo = element("picker.undo", preferred: app.buttons["picker.undo"])
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()

        XCTAssertTrue(waitForLabel(title, "Nothing logged yet", timeout: 5))
    }

    func testTapDoesNotLog() {
        let title = app.staticTexts["picker.currentTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Nothing logged yet")

        let row = app.descendants(matching: .any)["picker.row.3m2uvdvq7622g"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertEqual(title.label, "Nothing logged yet")
        XCTAssertFalse(app.descendants(matching: .any)["picker.undo"].firstMatch.exists)
    }

    func testSearchFiltersRows() {
        let search = element("picker.search", preferred: app.textFields["picker.search"])
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("kur")

        let kurono = app.descendants(matching: .any)["picker.row.3mwz3ctxxnc26"].firstMatch
        let citizen = app.descendants(matching: .any)["picker.row.3m2uvdvq7622g"].firstMatch
        XCTAssertTrue(kurono.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForNonExistence(citizen, timeout: 3))

        let clear = element("picker.searchClear", preferred: app.buttons["picker.searchClear"])
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()

        XCTAssertTrue(citizen.waitForExistence(timeout: 5))
    }

    func testHistoryShowsLoggedWear() {
        let title = app.staticTexts["picker.currentTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Nothing logged yet")

        let row = app.descendants(matching: .any)["picker.row.3m2uvdvq7622g"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        XCTAssertTrue(waitForLabel(title, "Citizen Eco Drive E110-K16750", timeout: 5))

        let historyButton = element("picker.history", preferred: app.buttons["picker.history"])
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        let list = app.descendants(matching: .any)["history.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        let historyRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'history.row.'"))
            .firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.swipeLeft()

        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let pickerTitle = app.staticTexts["picker.currentTitle"]
        XCTAssertTrue(waitForLabel(pickerTitle, "Nothing logged yet", timeout: 5))
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

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
