import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class TransactionGroupingTests: XCTestCase {
    func testSaigonMidnightGroupsAndSortsNewestFirst() async {
        let formatter = ISO8601DateFormatter()
        let wallet = Wallet(name: "Ví")
        let category = Category(name: "Chi", kind: .expense)
        func transaction(_ date: String) -> Transaction {
            Transaction(amount: 1, kind: .expense, date: formatter.date(from: date)!, wallet: wallet, category: category)
        }
        let old = transaction("2026-10-31T23:59:00+07:00")
        let midnight = transaction("2026-11-01T00:00:00+07:00")
        let later = transaction("2026-11-01T00:01:00+07:00")
        let groups = TransactionGrouping.group([old, later, midnight])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].date, formatter.date(from: "2026-10-31T17:00:00Z"))
        XCTAssertEqual(groups[0].transactions.map(\.id), [later.id, midnight.id])
        XCTAssertEqual(groups[1].transactions.map(\.id), [old.id])
        XCTAssertEqual(TransactionGrouping.title(for: midnight.date, now: later.date), "Hôm nay")
        XCTAssertEqual(TransactionGrouping.title(for: old.date, now: later.date), "Hôm qua")
        XCTAssertTrue(TransactionGrouping.group([]).isEmpty)
        let historical = TransactionGrouping.title(for: old.date, now: formatter.date(from: "2026-11-10T00:00:00+07:00")!)
        XCTAssertTrue(historical.contains("31/10/2026"))
    }

    func testEqualTimestampsHaveDeterministicOrder() async {
        let wallet = Wallet(name: "Ví")
        let date = Date(timeIntervalSince1970: 0)
        let a = Transaction(amount: 1, kind: .transfer, date: date, wallet: wallet, toWallet: Wallet(name: "B"))
        let b = Transaction(amount: 2, kind: .transfer, date: date, wallet: wallet, toWallet: Wallet(name: "C"))
        XCTAssertEqual(TransactionGrouping.group([a, b])[0].transactions.map(\.id),
                       TransactionGrouping.group([b, a])[0].transactions.map(\.id))
    }
}
