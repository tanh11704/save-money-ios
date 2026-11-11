import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

final class StatsAnalyticsTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        LocalCalendar.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute, second: second))!
    }
    func testDailyCountsAndCompactFormatting() throws {
        for (year, month, count) in [(2026, 2, 28), (2028, 2, 29), (2026, 11, 30), (2026, 12, 31)] {
            let rows = try StatsService.dailyExpenses(month: ReportingMonth(year: year, month: month), transactions: [])
            XCTAssertEqual(rows.map(\.day), Array(1...count)); XCTAssertTrue(rows.allSatisfy { $0.expense == 0 })
        }
        XCTAssertEqual(MoneyFormatter.compact(1_250_000), "1,25tr")
        XCTAssertEqual(MoneyFormatter.compact(500_000), "500k")
        XCTAssertEqual(MoneyFormatter.compact(-1_200), "−1,2k")
        XCTAssertEqual(MoneyFormatter.compact(999), "999")
        XCTAssertEqual(MoneyFormatter.compact(Int64.min), "−9223372036854,77tr")
    }
    func testLocalMidnightBoundariesAndFlowExclusions() throws {
        let wallet = Wallet(name: "A"), other = Wallet(name: "B"), expense = Category(name: "Chi", kind: .expense), income = Category(name: "Thu", kind: .income)
        let records = [Transaction(amount: 10, kind: .expense, date: date(2026, 11, 14, 23, 59, 59), wallet: wallet, category: expense),
            Transaction(amount: 20, kind: .expense, date: date(2026, 11, 15), wallet: wallet, category: expense),
            Transaction(amount: 100, kind: .transfer, date: date(2026, 11, 15), wallet: wallet, toWallet: other),
            Transaction(amount: 100, kind: .income, date: date(2026, 11, 15), wallet: wallet, category: income)]
        let month = try ReportingMonth(year: 2026, month: 11)
        let daily = try StatsService.dailyExpenses(month: month, transactions: records)
        XCTAssertEqual(daily[13].expense, 10); XCTAssertEqual(daily[14].expense, 20)
        XCTAssertEqual(daily.reduce(Int64(0)) { $0 + $1.expense }, try StatsService.report(month: month, transactions: records).expense)
        XCTAssertEqual(StatsService.dailyAllowance(limit: 1_000, month: month), 33)
    }
    func testSlicesKeepUncategorizedAndAggregateRemainderWithoutLosingMoney() throws {
        let wallet = Wallet(name: "A"), month = ReportingMonth()
        let records = (1...7).map { i -> Transaction in
            let category = Category(name: "Danh mục \(i)", kind: .expense)
            return Transaction(amount: Int64(i), kind: .expense, wallet: wallet, category: category)
        } + [Transaction(amount: 100, kind: .expense, wallet: wallet)]
        let report = try StatsService.report(month: month, transactions: records)
        let slices = StatsService.expenseSlices(report)
        XCTAssertEqual(slices.count, 6); XCTAssertEqual(slices.last?.name, "Khác")
        XCTAssertEqual(slices.reduce(Int64(0)) { $0 + $1.amount }, report.expense)
        XCTAssertTrue(slices.contains { $0.name == "Không có danh mục" })
        XCTAssertEqual(Set(slices.map(\.id)).count, slices.count)
        let small = try StatsService.report(month: month, transactions: Array(records.prefix(3)))
        XCTAssertEqual(StatsService.expenseSlices(small).count, 3)
        XCTAssertFalse(StatsService.expenseSlices(small).contains { $0.key.isOther })
    }
}
