import XCTest

final class SmokeTests: XCTestCase {
    @MainActor func testDisabledTransactionSaveRemainsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-smoke", "transaction"]
        app.launch()
        let save = app.buttons["transaction.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isHittable)
        XCTAssertFalse(save.isEnabled)
        XCTAssertEqual(save.label, "Nhập số tiền")
        XCTAssertFalse(app.staticTexts["transaction.validation"].exists)
        app.buttons["keypad.hide"].tap()
        XCTAssertFalse(app.buttons["keypad.5"].exists)
        // Tap the prompt's hit area while the underlying save action stays disabled.
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["keypad.5"].waitForExistence(timeout: 5))
        app.buttons["keypad.5"].tap()
        app.buttons["keypad.0"].tap()
        app.buttons["keypad.000"].tap()
        if app.buttons["keypad.hide"].exists { app.buttons["keypad.hide"].tap() }
        // Match by identifier independently of Xcode's inferred SwiftUI element type.
        let category = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.category.")).firstMatch
        guard category.waitForExistence(timeout: 5) else {
            XCTFail("Fixture không có danh mục giao dịch"); return
        }
        for _ in 0..<3 {
            if category.isHittable { break }
            app.swipeUp()
        }
        guard category.isHittable else {
            XCTFail("Danh mục chưa nằm trong vùng chạm"); return
        }
        category.tap()
        XCTAssertEqual(save.label, "Lưu")
        XCTAssertTrue(save.isEnabled)
        app.terminate()
    }

    @MainActor private func check(_ screen: String, field: String, returnKey: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-smoke", screen]
        app.launch()
        let input = app.textFields[field]
        guard input.waitForExistence(timeout: 10) else {
            XCTFail("Không tìm thấy ô nhập \(field)"); return
        }
        input.tap()
        // A cold Simulator can drop the first focus event while opening its keyboard service.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 8) { input.tap() }
        guard app.keyboards.firstMatch.waitForExistence(timeout: 8) else {
            XCTFail("Bàn phím chưa mở cho \(screen)"); return
        }
        input.typeText("Ten moi")
        if returnKey { input.typeText("\n") }
        else {
            let done = app.buttons["keyboard.done"]
            let hittable = NSPredicate(format: "exists == true AND hittable == true")
            let ready = XCTNSPredicateExpectation(predicate: hittable, object: done)
            guard XCTWaiter.wait(for: [ready], timeout: 8) == .completed else {
                XCTFail("Nút Xong chưa sẵn sàng cho \(screen)"); return
            }
            done.tap()
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
