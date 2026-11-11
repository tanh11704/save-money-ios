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

    // MARK: - Weekly periods (Monday–Sunday, Asia/Saigon)

    func testWeekStartsMondayInSaigonRegardlessOfDeviceLocale() {
        // 11/11/2026 is a Wednesday; its week is Mon 9/11 – Sun 15/11.
        let week = StatsPeriod(kind: .week, containing: date(2026, 11, 11, 12))
        XCTAssertEqual(week.interval.start, date(2026, 11, 9))
        XCTAssertEqual(week.interval.end, date(2026, 11, 16))
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertEqual(week.title, "Tuần 9/11 – 15/11")
        XCTAssertEqual(StatsPeriod(kind: .week, containing: date(2026, 11, 15, 23, 59, 59)), week)
        XCTAssertEqual(StatsPeriod(kind: .week, containing: date(2026, 11, 16)), week.next)
        XCTAssertEqual(week.previous.interval.start, date(2026, 11, 2))
        XCTAssertEqual((0..<7).map { StatsPeriod.weekdayLabel(date(2026, 11, 9 + $0)) }, ["T2", "T3", "T4", "T5", "T6", "T7", "CN"])
    }

    func testWeekAcrossYearBoundaryAndNavigationLimits() {
        let week = StatsPeriod(kind: .week, containing: date(2026, 12, 31))
        XCTAssertEqual(week.interval.start, date(2026, 12, 28))
        XCTAssertEqual(week.interval.end, date(2027, 1, 4))
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertEqual(week.month, try ReportingMonth(year: 2026, month: 12))
        XCTAssertNil(week.next(upTo: week))
        XCTAssertEqual(week.previous.next(upTo: week), week)
        XCTAssertEqual(week.trailing(3).map(\.interval.start), [date(2026, 12, 14), date(2026, 12, 21), date(2026, 12, 28)])
    }

    func testMonthPeriodMatchesReportingMonth() throws {
        let month = try ReportingMonth(year: 2028, month: 2)
        let period = StatsPeriod(month: month)
        XCTAssertEqual(period, StatsPeriod(kind: .month, containing: date(2028, 2, 29, 23, 59, 59)))
        XCTAssertEqual(period.interval, month.interval)
        XCTAssertEqual(period.dayCount, 29)
        XCTAssertEqual(period.title, month.title)
        XCTAssertEqual(StatsPeriod(month: try ReportingMonth(year: 2027, month: 1)).shortTitle, "T1/27")
    }

    func testWeeklyReportAndDailyTotalsExcludeTransfersAndIncome() throws {
        let wallet = Wallet(name: "A"), other = Wallet(name: "B")
        let expense = Category(name: "Chi", kind: .expense), income = Category(name: "Thu", kind: .income)
        let records = [
            Transaction(amount: 5, kind: .expense, date: date(2026, 11, 8, 23, 59, 59), wallet: wallet, category: expense),  // previous Sunday
            Transaction(amount: 10, kind: .expense, date: date(2026, 11, 9), wallet: wallet, category: expense),             // Monday 00:00
            Transaction(amount: 20, kind: .expense, date: date(2026, 11, 15, 23, 59, 59), wallet: wallet, category: expense),// Sunday end
            Transaction(amount: 40, kind: .expense, date: date(2026, 11, 16), wallet: wallet, category: expense),            // next Monday
            Transaction(amount: 100, kind: .transfer, date: date(2026, 11, 10), wallet: wallet, toWallet: other),
            Transaction(amount: 300, kind: .income, date: date(2026, 11, 10), wallet: wallet, category: income)]
        let week = StatsPeriod(kind: .week, containing: date(2026, 11, 11))
        let report = try StatsService.report(period: week, transactions: records)
        XCTAssertEqual(report.expense, 30)
        XCTAssertEqual(report.income, 300)
        XCTAssertEqual(report.interval, week.interval)
        let daily = try StatsService.dailyExpenses(period: week, transactions: records)
        XCTAssertEqual(daily.map(\.expense), [10, 0, 0, 0, 0, 0, 20])
        XCTAssertEqual(daily.first?.date, date(2026, 11, 9))
        XCTAssertEqual(daily.reduce(Int64(0)) { $0 + $1.expense }, report.expense)
    }

    func testTrendSumsMatchIndividualReports() throws {
        let wallet = Wallet(name: "A"), expense = Category(name: "Chi", kind: .expense)
        let records = (0..<30).map { i in
            Transaction(amount: Int64(i + 1) * 1_000, kind: .expense, date: date(2026, 10, 15).addingTimeInterval(Double(i) * 86_400), wallet: wallet, category: expense)
        }
        for kind in StatsPeriodKind.allCases {
            let end = StatsPeriod(kind: kind, containing: date(2026, 11, 11))
            let points = try StatsService.trend(ending: end, count: 4, transactions: records)
            XCTAssertEqual(points.count, 4)
            XCTAssertEqual(points.last?.period, end)
            XCTAssertEqual(points.map(\.period), end.trailing(4))
            for point in points {
                XCTAssertEqual(point.expense, try StatsService.report(period: point.period, transactions: records).expense)
            }
        }
    }

    func testCurrentWeekComparesSameElapsedDays() throws {
        let wallet = Wallet(name: "A"), expense = Category(name: "Chi", kind: .expense)
        let records = [
            Transaction(amount: 100, kind: .expense, date: date(2026, 11, 3), wallet: wallet, category: expense),  // last Tue: counted
            Transaction(amount: 900, kind: .expense, date: date(2026, 11, 5), wallet: wallet, category: expense),  // last Thu: after Wed, excluded
            Transaction(amount: 50, kind: .expense, date: date(2026, 11, 10), wallet: wallet, category: expense)]
        let week = StatsPeriod(kind: .week, containing: date(2026, 11, 11))
        let now = date(2026, 11, 11, 18)
        let result = try StatsService.comparison(period: week, now: now, transactions: records)
        XCTAssertEqual(result.previousRange, DateInterval(start: date(2026, 11, 2), end: date(2026, 11, 5)))
        XCTAssertEqual(result.expense.current, 50)
        XCTAssertEqual(result.expense.previous, 100)
        XCTAssertEqual(result.label, "so với T2–T4 tuần trước")
        let past = try StatsService.comparison(period: week.previous, now: now, transactions: records)
        XCTAssertEqual(past.expense.current, 1_000)
        XCTAssertEqual(past.label, "so với tuần trước")
    }
}
