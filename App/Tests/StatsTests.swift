import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

@MainActor
final class StatsTests: XCTestCase {
    @MainActor private final class Fixture {
        let container: ModelContainer
        let a = Wallet(name: "Tiền mặt", openingBalance: 1_000_000)
        let b = Wallet(name: "Ngân hàng", openingBalance: 2_000_000)
        let food = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
        let travel = Category(name: "Đi lại", kind: .expense, icon: "bus")
        let shopping = Category(name: "Mua sắm", kind: .expense, icon: "bag")
        let salary = Category(name: "Lương", kind: .income, icon: "banknote")
        let other = Category(name: "Thu khác", kind: .income)
        var reader: ModelContext?

        init() throws {
            let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            container.mainContext.autosaveEnabled = false
            [a, b].forEach { container.mainContext.insert($0) }
            [food, travel, shopping, salary, other].forEach { container.mainContext.insert($0) }
            try container.mainContext.save()
        }

        @discardableResult
        func add(_ amount: Int64, kind: TransactionKind = .expense, category: Category? = nil,
                 date: Date? = nil, wallet: Wallet? = nil, uncategorized: Bool = false) -> Transaction {
            let source = wallet ?? a
            let selectedCategory = kind == .transfer || uncategorized ? nil : category ?? (kind == .income ? salary : food)
            let transaction = Transaction(amount: amount, kind: kind,
                date: date ?? ISO8601DateFormatter().date(from: "2026-11-15T12:00:00+07:00")!,
                wallet: source, toWallet: kind == .transfer ? (source.id == a.id ? b : a) : nil, category: selectedCategory)
            container.mainContext.insert(transaction)
            return transaction
        }

        func transactions() throws -> [Transaction] {
            try container.mainContext.save()
            let context = ModelContext(container)
            reader = context
            return try context.fetch(FetchDescriptor<Transaction>())
        }

        func report(_ year: Int = 2026, _ month: Int = 11) throws -> StatsService.Report {
            try container.mainContext.save()
            let context = ModelContext(container)
            reader = context
            return try StatsService.report(year: year, month: month, transactions: context.fetch(FetchDescriptor<Transaction>()))
        }
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testEmptyMonthHasZeroTotalsAndNoCategories() async throws {
        let f = try Fixture()
        let report = try f.report()
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.income, 0)
        XCTAssertEqual(report.expense, 0)
        XCTAssertEqual(report.difference, 0)
        XCTAssertTrue(report.expenses.isEmpty)
        XCTAssertTrue(report.incomes.isEmpty)
        XCTAssertEqual(StatsPercentage.tenths(amount: 0, total: 0), 0)
    }

    func testTransferOnlyHasNoFlowsOrCategories() async throws {
        let f = try Fixture()
        f.add(300_000, kind: .transfer)
        f.add(100_000, kind: .transfer, wallet: f.b)
        let report = try f.report()
        XCTAssertFalse(report.isEmpty) // There are transactions, just no income/expense.
        XCTAssertEqual(report.income, 0)
        XCTAssertEqual(report.expense, 0)
        XCTAssertEqual(report.difference, 0)
        XCTAssertTrue(report.expenses.isEmpty)
        XCTAssertTrue(report.incomes.isEmpty)
        XCTAssertTrue(report.transactions(for: .init(kind: .transfer, categoryID: nil)).isEmpty)
    }

    func testSaigonMonthEndExcludesNextMidnightAndNextMinute() async throws {
        let f = try Fixture()
        f.add(100, date: date("2026-10-31T23:59:00+07:00"))
        f.add(200, date: date("2026-11-01T00:00:00+07:00"))
        f.add(300, date: date("2026-11-01T00:01:00+07:00"))
        XCTAssertEqual(try f.report(2026, 10).expense, 100)
        XCTAssertEqual(try f.report(2026, 11).expense, 500)
        let november = try ReportingMonth(year: 2026, month: 11)
        XCTAssertEqual(november.interval.start, date("2026-10-31T17:00:00Z"))
        XCTAssertEqual(november.interval.end, date("2026-11-30T17:00:00Z"))
    }

    func testLeapFebruaryIncludesTwentyNinthAndExcludesMarch() async throws {
        let f = try Fixture()
        f.add(50, date: date("2024-02-29T00:00:00+07:00"))
        f.add(70, date: date("2024-02-29T23:59:00+07:00"))
        f.add(200, date: date("2024-03-01T00:00:00+07:00"))
        XCTAssertEqual(try f.report(2024, 2).expense, 120)
        XCTAssertEqual(try f.report(2024, 3).expense, 200)
    }

    func testArchivedWalletsAndCategoriesStillCountAndDrillDown() async throws {
        let f = try Fixture()
        let expense = f.add(150)
        f.add(250, kind: .income)
        f.a.isArchived = true
        f.food.isArchived = true
        f.salary.isArchived = true
        let report = try f.report()
        XCTAssertEqual(report.expense, 150)
        XCTAssertEqual(report.income, 250)
        XCTAssertEqual(report.expenses.first?.name, "Ăn uống")
        XCTAssertEqual(report.incomes.first?.name, "Lương")
        XCTAssertEqual(report.transactions(for: .init(kind: .expense, categoryID: f.food.id)).map(\.id), [expense.id])
    }

    func testHandCalculatedSixExpensesTwoIncomesAndTwoTransfers() async throws {
        let f = try Fixture()
        // Independent arithmetic: food 120k+80k=200k, travel 50k+50k=100k,
        // shopping 200k+100k=300k; expense=600k. Income=1m+200k=1.2m.
        f.add(120_000, category: f.food)
        f.add(80_000, category: f.food)
        f.add(50_000, category: f.travel)
        f.add(50_000, category: f.travel)
        f.add(200_000, category: f.shopping)
        f.add(100_000, category: f.shopping)
        f.add(1_000_000, kind: .income, category: f.salary, wallet: f.b)
        f.add(200_000, kind: .income, category: f.other, wallet: f.b)
        let beforeTransfers = try f.report()
        f.add(300_000, kind: .transfer)
        f.add(100_000, kind: .transfer, wallet: f.b)
        let report = try f.report()
        XCTAssertEqual(report.transactions.count, 10)
        XCTAssertEqual(report.income, 1_200_000)
        XCTAssertEqual(report.expense, 600_000)
        XCTAssertEqual(report.difference, 600_000)
        XCTAssertEqual(report.income, beforeTransfers.income)
        XCTAssertEqual(report.expense, beforeTransfers.expense)
        XCTAssertEqual(report.expenses.map(\.name), ["Mua sắm", "Ăn uống", "Đi lại"])
        XCTAssertEqual(report.expenses.map(\.amount), [300_000, 200_000, 100_000])
        XCTAssertEqual(report.expenses.map(\.percentageText), ["50,0%", "33,3%", "16,7%"])
        XCTAssertEqual(report.incomes.map(\.percentageText), ["83,3%", "16,7%"])
        XCTAssertEqual(report.expenses.reduce(Int64(0)) { $0 + $1.amount }, report.expense)
        XCTAssertEqual(report.incomes.reduce(Int64(0)) { $0 + $1.amount }, report.income)
        XCTAssertEqual(report.expenses.reduce(0) { $0 + $1.percentageTenths }, 1_000)
        for row in report.expenses + report.incomes {
            let details = report.transactions(for: row.key)
            XCTAssertEqual(details.count, row.key.kind == .expense ? 2 : 1)
            XCTAssertEqual(details.reduce(Int64(0)) { $0 + $1.amount }, row.amount)
            XCTAssertTrue(details.allSatisfy { $0.kindRaw != "transfer" })
        }
    }

    func testMissingCategoryIsReportedSeparatelyForIncomeAndExpense() async throws {
        let f = try Fixture()
        f.add(10)
        let missingExpense = f.add(20, uncategorized: true)
        let missingIncome = f.add(30, kind: .income, uncategorized: true)
        let report = try f.report()
        XCTAssertEqual(report.expense, 30)
        XCTAssertEqual(report.income, 30)
        let expense = try XCTUnwrap(report.expenses.first { $0.key.categoryID == nil })
        let income = try XCTUnwrap(report.incomes.first { $0.key.categoryID == nil })
        XCTAssertEqual(expense.name, "Không có danh mục")
        XCTAssertEqual(income.name, "Không có danh mục")
        XCTAssertNotEqual(expense.id, income.id)
        XCTAssertEqual(report.transactions(for: expense.key).map(\.id), [missingExpense.id])
        XCTAssertEqual(report.transactions(for: income.key).map(\.id), [missingIncome.id])
        XCTAssertEqual(report.expenses.reduce(Int64(0)) { $0 + $1.amount }, report.expense)
        XCTAssertThrowsError(try BalanceCalculator.flowTotals(transactions: report.transactions))
    }

    func testUnusedZeroTotalCategoriesAreHiddenAndIncomeOnlyWorks() async throws {
        let f = try Fixture()
        f.add(1_000, kind: .income)
        let report = try f.report()
        XCTAssertTrue(report.expenses.isEmpty)
        XCTAssertEqual(report.incomes.count, 1)
        XCTAssertEqual(report.incomes.first?.percentageText, "100,0%")
        XCTAssertFalse(report.incomes.contains { $0.key.categoryID == f.other.id })
    }

    func testNegativeDifferenceAndExplicitSigns() async throws {
        let f = try Fixture()
        f.add(300)
        f.add(100, kind: .income)
        let report = try f.report()
        XCTAssertEqual(report.difference, -200)
        XCTAssertEqual(report.differenceText, "−200 ₫")
        XCTAssertEqual(report.incomeText, "+100 ₫")
        XCTAssertEqual(report.expenseText, "−300 ₫")
    }

    func testInt64OverflowThrowsForBothFlowKinds() async throws {
        for kind in [TransactionKind.income, .expense] {
            let f = try Fixture()
            f.add(Int64.max, kind: kind)
            f.add(1, kind: kind, category: kind == .income ? f.other : f.travel)
            XCTAssertThrowsError(try f.report()) { XCTAssertEqual($0 as? BalanceCalculator.CalculationError, .overflow) }
        }
    }

    func testLargestValidTotalsAndPercentagesDoNotMultiplyOverflow() async throws {
        let f = try Fixture()
        f.add(Int64.max, kind: .income)
        f.add(Int64.max)
        let report = try f.report()
        XCTAssertEqual(report.difference, 0)
        XCTAssertEqual(report.incomes.first?.percentageText, "100,0%")
        XCTAssertEqual(report.expenses.first?.percentageText, "100,0%")
        XCTAssertEqual(StatsPercentage.tenths(amount: Int64.max - 1, total: Int64.max), 1_000)
    }

    func testEqualAmountsHaveStableOrderAndPercentagesRoundHalfUp() async throws {
        let f = try Fixture()
        let a = f.add(1, category: f.food)
        f.add(1, category: f.travel, date: a.date)
        let report = try f.report()
        XCTAssertEqual(report.expenses.map(\.name), ["Ăn uống", "Đi lại"])
        XCTAssertEqual(StatsPercentage.tenths(amount: 1, total: 16), 63) // 6.25% -> 6.3%.
        XCTAssertEqual(StatsPercentage.tenths(amount: 1, total: 3), 333)
    }

    func testInvalidAmountsFailButInvalidRecordsOutsideMonthDoNotPolluteIt() async throws {
        let f = try Fixture()
        let invalid = f.add(0, date: date("2026-10-10T00:00:00+07:00"))
        f.add(50)
        XCTAssertEqual(try f.report().expense, 50)
        invalid.date = date("2026-11-01T00:00:00+07:00")
        XCTAssertThrowsError(try f.report())
    }

    func testMonthSelectionAndInvalidInputs() async throws {
        let current = try ReportingMonth(year: 2026, month: 11)
        XCTAssertNil(current.next(upTo: current))
        XCTAssertEqual(current.previous?.next(upTo: current), current)
        XCTAssertEqual(try ReportingMonth(year: 2027, month: 1).clamped(to: current), current)
        XCTAssertEqual(try ReportingMonth(year: 2026, month: 1).previous, try ReportingMonth(year: 2025, month: 12))
        XCTAssertNil(try ReportingMonth(year: 1, month: 1).previous)
        for (year, month) in [(0, 1), (10_000, 1), (2026, 0), (2026, 13)] {
            XCTAssertThrowsError(try StatsService.report(year: year, month: month, transactions: []))
        }
    }

    func testCreateUpdateDeleteReflectImmediatelyWithoutReportCache() async throws {
        let f = try Fixture()
        let service = TransactionService(container: f.container)
        var draft = TransactionDraft(amount: 100, date: date("2026-11-10T12:00:00+07:00"), wallet: f.a, category: f.food)
        let id = try service.create(draft)
        XCTAssertEqual(try f.report().expense, 100)
        draft.amount = 250
        draft.category = f.travel
        try service.update(id: id, with: draft)
        let edited = try f.report()
        XCTAssertEqual(edited.expense, 250)
        XCTAssertEqual(edited.expenses.first?.key.categoryID, f.travel.id)
        draft.date = date("2026-10-31T23:59:00+07:00")
        try service.update(id: id, with: draft)
        XCTAssertTrue(try f.report().isEmpty)
        XCTAssertEqual(try f.report(2026, 10).expense, 250)
        try service.delete(id: id)
        XCTAssertTrue(try f.report(2026, 10).isEmpty)
    }

    // MARK: - Payday month cycles

    private func withStartDay(_ day: Int, _ body: () throws -> Void) rethrows {
        let suite = "MonthCycle.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let previous = MonthCycle.defaults
        MonthCycle.defaults = defaults
        defer { MonthCycle.defaults = previous; defaults.removePersistentDomain(forName: suite) }
        MonthCycle.startDay = day
        try body()
    }

    private func local(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T00:00:00+07:00")! }

    func testDefaultStartDayKeepsCalendarMonths() throws {
        try withStartDay(1) {
            let month = ReportingMonth(containing: local("2026-11-12"))
            XCTAssertEqual(month, try ReportingMonth(year: 2026, month: 11))
            XCTAssertEqual(month.interval, DateInterval(start: local("2026-11-01"), end: local("2026-12-01")))
            XCTAssertEqual(month.title, "Tháng 11/2026")
        }
    }

    func testLateStartDayNamesCycleAfterTheMonthItEndsIn() throws {
        try withStartDay(25) {
            let november = try ReportingMonth(year: 2026, month: 11)
            XCTAssertEqual(november.interval, DateInterval(start: local("2026-10-25"), end: local("2026-11-25")))
            XCTAssertEqual(ReportingMonth(containing: local("2026-10-25")), november)
            XCTAssertEqual(ReportingMonth(containing: local("2026-11-24").addingTimeInterval(86_399)), november)
            XCTAssertEqual(ReportingMonth(containing: local("2026-11-25")), try ReportingMonth(year: 2026, month: 12))
            XCTAssertEqual(ReportingMonth(containing: local("2026-12-30")), try ReportingMonth(year: 2027, month: 1))
            XCTAssertEqual(november.title, "Tháng 11/2026 (25/10–24/11)")
            XCTAssertEqual(november.dayCount, 31)
        }
    }

    func testEarlyStartDayNamesCycleAfterTheMonthItStartsIn() throws {
        try withStartDay(5) {
            let november = try ReportingMonth(year: 2026, month: 11)
            XCTAssertEqual(november.interval, DateInterval(start: local("2026-11-05"), end: local("2026-12-05")))
            XCTAssertEqual(ReportingMonth(containing: local("2026-11-04")), try ReportingMonth(year: 2026, month: 10))
            XCTAssertEqual(ReportingMonth(containing: local("2026-11-05")), november)
        }
    }

    func testStartDayPastMonthEndClampsAndCyclesStayContiguous() throws {
        try withStartDay(31) {
            let march = try ReportingMonth(year: 2026, month: 3)
            XCTAssertEqual(march.interval, DateInterval(start: local("2026-02-28"), end: local("2026-03-31")))
            var month = try ReportingMonth(year: 2026, month: 1)
            for _ in 0..<24 {
                let next = month.next!
                XCTAssertEqual(month.interval.end, next.interval.start)
                XCTAssertEqual(ReportingMonth(containing: month.interval.start), month)
                XCTAssertEqual(ReportingMonth(containing: month.interval.end.addingTimeInterval(-1)), month)
                month = next
            }
        }
    }

    func testReportsAndComparisonFollowPaydayCycle() throws {
        let f = try Fixture()
        try withStartDay(25) {
            f.add(100_000, date: local("2026-10-24"))
            f.add(200_000, date: local("2026-10-25"))
            f.add(300_000, date: local("2026-11-24"))
            f.add(400_000, date: local("2026-11-25"))
            let november = try ReportingMonth(year: 2026, month: 11)
            let transactions = try f.transactions()
            XCTAssertEqual(try StatsService.report(month: november, transactions: transactions).expense, 500_000)
            XCTAssertEqual(try StatsService.dailyExpenses(month: november, transactions: transactions).count, 31)
            XCTAssertEqual(StatsService.dailyAllowance(limit: 3_100_000, month: november), 100_000)
            let comparison = try StatsService.comparison(month: november, now: local("2026-10-26").addingTimeInterval(3_600), transactions: transactions)
            XCTAssertEqual(comparison.currentRange, DateInterval(start: local("2026-10-25"), end: local("2026-10-27")))
            XCTAssertEqual(comparison.previousRange, DateInterval(start: local("2026-09-25"), end: local("2026-09-27")))
            XCTAssertEqual(comparison.label, "so với 25/9–26/9")
        }
    }
}
