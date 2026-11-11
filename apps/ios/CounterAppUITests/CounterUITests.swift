// XCUITest UI tests: launch the app on a simulator and tap like a user.
import XCTest

final class CounterUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testStartsAtZero() {
        XCTAssertEqual(app.staticTexts["count_label"].label, "Count: 0")
    }

    func testIncrementDecrementReset() {
        app.buttons["increment_button"].tap()
        app.buttons["increment_button"].tap()
        XCTAssertEqual(app.staticTexts["count_label"].label, "Count: 2")

        app.buttons["decrement_button"].tap()
        XCTAssertEqual(app.staticTexts["count_label"].label, "Count: 1")

        app.buttons["reset_button"].tap()
        XCTAssertEqual(app.staticTexts["count_label"].label, "Count: 0")
    }
}
