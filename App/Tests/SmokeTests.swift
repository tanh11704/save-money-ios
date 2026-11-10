import XCTest
@testable import SaveMoney

final class SmokeTests: XCTestCase {
    func testApplicationModuleLoads() {
        XCTAssertEqual(String(reflecting: SaveMoneyApp.self), "SaveMoney.SaveMoneyApp")
    }
}

