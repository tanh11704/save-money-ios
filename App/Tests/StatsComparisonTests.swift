import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

final class StatsComparisonTests: XCTestCase {
    func testBalanceTrendIncludesExpensesAndHandlesCrossingZero() throws {
        let wallet = Wallet(name: "Cash"), expense = Category(name: "Food", kind: .expense), income = Category(name: "Salary", kind: .income)
        let records = [Transaction(amount: 100, kind: .expense, date: date(2026, 10, 1), wallet: wallet, category: expense), Transaction(amount: 200, kind: .income, date: date(2026, 11, 1), wallet: wallet, category: income)]
        let result = try StatsService.comparison(month: ReportingMonth(year: 2026, month: 11), now: date(2026, 11, 10), transactions: records)
        XCTAssertEqual(result.balance?.previous, -100)
        XCTAssertEqual(result.balance?.current, 200)
        XCTAssertEqual(result.balance?.difference, 300)
        XCTAssertTrue(result.balance?.text.hasPrefix("Tăng") == true)
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { LocalCalendar.calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    func testCurrentMonthUsesSameDaysAndExcludesLaterTransactions() throws {
        let wallet = Wallet(name: "A"), category = Category(name: "Chi", kind: .expense)
        let records = [Transaction(amount: 100, kind: .expense, date: date(2026, 10, 10), wallet: wallet, category: category),
            Transaction(amount: 500, kind: .expense, date: date(2026, 10, 20), wallet: wallet, category: category),
            Transaction(amount: 150, kind: .expense, date: date(2026, 11, 10), wallet: wallet, category: category),
            Transaction(amount: 900, kind: .expense, date: date(2026, 11, 11), wallet: wallet, category: category)]
        let result = try StatsService.comparison(month: ReportingMonth(year: 2026, month: 11), now: date(2026, 11, 10), transactions: records)
        XCTAssertEqual(result.previousRange, DateInterval(start: date(2026, 10, 1), end: date(2026, 10, 11)))
        XCTAssertEqual(result.expense.current, 150); XCTAssertEqual(result.expense.previous, 100)
        XCTAssertEqual(result.expense.percentageTenths, 500); XCTAssertEqual(result.label, "so với 1–10/10")
    }
    func testShortPreviousMonthAndPastMonthAndYearBoundary() throws {
        let march = try StatsService.comparison(month: ReportingMonth(year: 2026, month: 3), now: date(2026, 3, 31), transactions: [])
        XCTAssertEqual(march.previousRange.end, date(2026, 3, 1))
        let january = try StatsService.comparison(month: ReportingMonth(year: 2026, month: 1), now: date(2026, 11, 10), transactions: [])
        XCTAssertEqual(january.previousRange, DateInterval(start: date(2025, 12, 1), end: date(2026, 1, 1)))
        XCTAssertEqual(january.currentRange.end, date(2026, 2, 1)); XCTAssertNil(january.expense.percentageTenths)
    }
    func testPreviousOnlyCategoriesAndTransfersAndPercentageClamp() throws {
        let wallet = Wallet(name: "A"), other = Wallet(name: "B"), category = Category(name: "Chi cũ", kind: .expense)
        let records = [Transaction(amount: 100, kind: .expense, date: date(2026, 10, 1), wallet: wallet, category: category),
            Transaction(amount: 1, kind: .income, date: date(2026, 10, 1), wallet: wallet, category: Category(name: "Thu", kind: .income)),
            Transaction(amount: 999_999, kind: .income, date: date(2026, 11, 1), wallet: wallet, category: Category(name: "Thu", kind: .income)),
            Transaction(amount: 500, kind: .transfer, date: date(2026, 11, 1), wallet: wallet, toWallet: other)]
        let result = try StatsService.comparison(month: ReportingMonth(year: 2026, month: 11), now: date(2026, 11, 10), transactions: records)
        XCTAssertEqual(result.expenseByCategory[category.id]?.current, 0)
        XCTAssertEqual(result.expenseByCategory[category.id]?.percentageTenths, -1_000)
        XCTAssertEqual(result.income.percentageTenths, 9_999); XCTAssertEqual(result.expense.current, 0)
    }
}
