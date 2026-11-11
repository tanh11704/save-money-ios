import XCTest

final class SmokeTests: XCTestCase {
    @MainActor private func check(_ screen: String, field: String, returnKey: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-smoke", screen]
        app.launch()
        let input = app.textFields[field]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        // A cold Simulator can drop the first focus event while opening its keyboard service.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 8) { input.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        input.typeText("Ten moi")
        if returnKey { input.typeText("\n") }
        else {
            XCTAssertTrue(app.buttons["keyboard.done"].waitForExistence(timeout: 5))
            app.buttons["keyboard.done"].tap()
        }
        let gone = NSPredicate(format: "count == 0")
        expectation(for: gone, evaluatedWith: app.keyboards)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.keyboards.count, 0)
        app.terminate()
    }
    @MainActor func testWalletDoneClosesKeyboard() { check("wallet", field: "wallet.name") }
    @MainActor func testCategoryDoneClosesKeyboard() { check("category", field: "category.name") }
    @MainActor func testRecurringDoneClosesKeyboard() { check("recurring", field: "recurring.name") }
    @MainActor func testWalletReturnClosesKeyboard() { check("wallet", field: "wallet.name", returnKey: true) }
}
