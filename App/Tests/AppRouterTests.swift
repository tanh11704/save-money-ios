import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class AppRouterTests: XCTestCase {
    func testTransferRouteDoesNotReadWallets() {
        let id = UUID()
        XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://transfer?from=\(id.uuidString)")!), .transfer(from: id))
        XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://transfer?from=invalid")!), .transfer(from: nil))
        XCTAssertNil(AppRoute.parse(URL(string: "savemoney://transfer?from=a&from=b")!))
    }
    func testValidAndInvalidURLsNeverAcceptOutOfRangeOrMalformedAmounts() {
        XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://add?kind=expense&amount=50000")!), .add(kind: .expense, amount: 50_000))
        XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://history")!), .history)
        XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://stats")!), .stats)
        for amount in ["0", "-1", "1000000000000", "1e9", "abc"] {
            XCTAssertEqual(AppRoute.parse(URL(string: "savemoney://add?kind=unknown&amount=" + amount)!), .add(kind: nil, amount: nil))
        }
        XCTAssertNil(AppRoute.parse(URL(string: "https://add?amount=50000")!))
        XCTAssertNil(AppRoute.parse(URL(string: "savemoney://delete")!))
        XCTAssertNil(AppRoute.parse(URL(string: "savemoney://add?amount=1&amount=2")!))
    }
    @MainActor func testLockedRouteStaysPendingUntilUnlockAndDoesNotSave() {
        let router = AppRouter(); router.enqueue(.add(kind: .income, amount: 100))
        XCTAssertNil(router.take(unlocked: false)); XCTAssertNotNil(router.pending)
        XCTAssertEqual(router.take(unlocked: true), .add(kind: .income, amount: 100)); XCTAssertNil(router.pending)
    }
}
