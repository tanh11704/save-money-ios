import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

@MainActor
final class EngagementTests: XCTestCase {
    private func local(_ text: String, hour: Int = 12) -> Date {
        ISO8601DateFormatter().date(from: text + String(format: "T%02d:00:00+07:00", hour))!
    }
    private let cash = Wallet(name: "Tiền mặt")
    private let bank = Wallet(name: "Ngân hàng", kind: .bank)
    private let food = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
    private let travel = Category(name: "Đi lại", kind: .expense, icon: "bus")

    private func expense(_ amount: Int64, _ day: String, _ category: Category? = nil) -> Transaction {
        Transaction(amount: amount, kind: .expense, date: local(day), wallet: cash, category: category ?? food)
    }

    private func withCycle(startDay: Int = 1, _ body: () throws -> Void) rethrows {
        let suite = "Engagement.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let previousCycle = MonthCycle.defaults, previousMain = MainWallet.defaults
        MonthCycle.defaults = defaults; MainWallet.defaults = defaults
        defer { MonthCycle.defaults = previousCycle; MainWallet.defaults = previousMain; defaults.removePersistentDomain(forName: suite) }
        MonthCycle.startDay = startDay
        try body()
    }

    func testBudgetPaceComparesSpendingWithEvenPace() throws {
        try withCycle {
            let november = try ReportingMonth(year: 2026, month: 11) // 30 days
            // Day 15 of 30: an even pace allows 1.500.000 of 3.000.000.
            let fast = try XCTUnwrap(BudgetPace.make(spent: 2_100_000, limit: 3_000_000, month: november, now: local("2026-11-15")))
            XCTAssertEqual(fast.elapsedDays, 15)
            XCTAssertEqual(fast.expected, 1_500_000)
            XCTAssertEqual(fast.difference, 600_000)
            XCTAssertEqual(fast.status, .ahead)
            XCTAssertEqual(fast.text, "Chi nhanh hơn kế hoạch 600k")
            XCTAssertEqual(BudgetPace.make(spent: 1_550_000, limit: 3_000_000, month: november, now: local("2026-11-15"))?.status, .onTrack)
            XCTAssertEqual(BudgetPace.make(spent: 500_000, limit: 3_000_000, month: november, now: local("2026-11-15"))?.status, .behind)
            XCTAssertNil(BudgetPace.make(spent: 1, limit: 3_000_000, month: november, now: local("2026-12-02")))
            XCTAssertNil(BudgetPace.make(spent: 1, limit: 0, month: november, now: local("2026-11-15")))
        }
    }

    func testBudgetPaceExpectsFixedCostsInFullAndSpreadsOnlyTheRest() throws {
        try withCycle {
            let november = try ReportingMonth(year: 2026, month: 11) // 30 days
            // Day 1, rent 4.000.000 paid plus 200.000 food: 4.000.000 + 6.000.000 / 30 = 4.200.000 expected.
            let paid = try XCTUnwrap(BudgetPace.make(spent: 4_200_000, limit: 10_000_000, month: november,
                                                     fixed: FixedCosts.Totals(spent: 4_000_000, reserved: 0), now: local("2026-11-01")))
            XCTAssertEqual(paid.expected, 4_200_000)
            XCTAssertEqual(paid.status, .onTrack)
            XCTAssertEqual(BudgetPace.make(spent: 4_200_000, limit: 10_000_000, month: november, now: local("2026-11-01"))?.status, .ahead)
            // Rent still to come is set aside but not expected yet.
            let upcoming = try XCTUnwrap(BudgetPace.make(spent: 200_000, limit: 10_000_000, month: november,
                                                         fixed: FixedCosts.Totals(spent: 0, reserved: 4_000_000), now: local("2026-11-01")))
            XCTAssertEqual(upcoming.expected, 200_000)
            // Fixed costs above the limit: nothing left to spread.
            XCTAssertEqual(BudgetPace.make(spent: 0, limit: 1_000, month: november,
                                           fixed: FixedCosts.Totals(spent: 1_500, reserved: 0), now: local("2026-11-15"))?.expected, 1_500)
        }
    }

    func testLoggingStreakCountsBackFromTodayOrYesterday() {
        let transactions = [expense(1, "2026-11-12"), expense(1, "2026-11-13"), expense(1, "2026-11-14"), expense(1, "2026-11-10")]
        XCTAssertEqual(LoggingStreak.days(transactions: transactions, now: local("2026-11-14", hour: 22)), 3)
        // Nothing logged on the 15th yet: the streak from yesterday still counts.
        XCTAssertEqual(LoggingStreak.days(transactions: transactions, now: local("2026-11-15", hour: 8)), 3)
        XCTAssertFalse(LoggingStreak.hasLoggedToday(transactions: transactions, now: local("2026-11-15", hour: 8)))
        XCTAssertEqual(LoggingStreak.days(transactions: transactions, now: local("2026-11-17")), 0)
        XCTAssertEqual(LoggingStreak.days(transactions: [], now: local("2026-11-17")), 0)
    }

    func testMainWalletWinsForExpensesButNotTransfers() {
        withCycle {
            let recent = RecentSelectionStore(defaults: UserDefaults(suiteName: "Recent.\(UUID().uuidString)")!)
            let wallets = [cash, bank]
            let expense = TransactionFormSelection.restoring(TransactionDraft(kind: .expense), wallets: wallets, categories: [food],
                                                            recent: recent, preferredWalletID: bank.id)
            XCTAssertEqual(expense.wallet?.id, bank.id)
            let income = TransactionFormSelection.restoring(TransactionDraft(kind: .income), wallets: wallets, categories: [],
                                                           recent: recent, preferredWalletID: bank.id)
            XCTAssertEqual(income.wallet?.id, bank.id)
            let transfer = TransactionFormSelection.restoring(TransactionDraft(kind: .transfer), wallets: wallets, categories: [],
                                                             recent: recent, preferredWalletID: bank.id)
            XCTAssertEqual(transfer.wallet?.id, cash.id, "Transfers keep their own last-used source")
            bank.isArchived = true
            defer { bank.isArchived = false }
            let archived = TransactionFormSelection.restoring(TransactionDraft(kind: .expense), wallets: wallets, categories: [food],
                                                             recent: recent, preferredWalletID: bank.id)
            XCTAssertEqual(archived.wallet?.id, cash.id, "An archived main wallet is ignored")

            MainWallet.id = bank.id
            XCTAssertEqual(MainWallet.id, bank.id)
            MainWallet.id = nil
            XCTAssertNil(MainWallet.id)
        }
    }

    func testHeatmapAndHistoryDayFilter() throws {
        try withCycle {
            let november = try ReportingMonth(year: 2026, month: 11)
            let transfer = Transaction(amount: 9_000_000, kind: .transfer, date: local("2026-11-03"), wallet: cash, toWallet: bank)
            let rows = [expense(100_000, "2026-11-03"), expense(50_000, "2026-11-03"), expense(400_000, "2026-11-05"), transfer, expense(1, "2026-10-31")]
            let totals = SpendingHeatmap.dailyExpenses(transactions: rows, in: november.interval)
            XCTAssertEqual(totals.count, 2)
            XCTAssertEqual(totals[LocalCalendar.calendar.startOfDay(for: local("2026-11-03"))], 150_000)
            XCTAssertEqual(SpendingHeatmap.level(400_000, maximum: 400_000), 4)
            XCTAssertEqual(SpendingHeatmap.level(150_000, maximum: 400_000), 2)
            XCTAssertEqual(SpendingHeatmap.level(0, maximum: 400_000), 0)

            var filter = HistoryFilter()
            filter.day = local("2026-11-03", hour: 0)
            XCTAssertEqual(filter.apply(to: rows).count, 3)
        }
    }

    func testInsightsExplainTheReport() throws {
        try withCycle {
            let november = try ReportingMonth(year: 2026, month: 11)
            let rows = [
                expense(300_000, "2026-10-10", food),
                expense(600_000, "2026-11-07", food),   // Saturday
                expense(200_000, "2026-11-08", travel), // Sunday
                expense(100_000, "2026-11-10", food)
            ]
            let report = try StatsService.report(month: november, transactions: rows)
            let comparison = try StatsService.comparison(month: november, now: november.interval.end, transactions: rows)
            let texts = StatsInsight.make(report: report, comparison: comparison, kind: .month).map(\.text)
            XCTAssertTrue(texts.contains { $0.hasPrefix("Ăn uống tăng") }, "\(texts)")
            XCTAssertTrue(texts.contains("Cuối tuần chiếm 88,9% chi tiêu"), "\(texts)")
            XCTAssertTrue(texts.contains { $0.hasPrefix("Ngày chi nhiều nhất: 7/11") }, "\(texts)")
            XCTAssertLessThanOrEqual(texts.count, 3)
        }
    }

    func testWalletAppearanceRoundTrip() {
        let suite = "Appearance.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        XCTAssertNil(WalletAppearance.colorIndex(for: id, defaults: defaults))
        WalletAppearance.setColorIndex(3, for: id, defaults: defaults)
        XCTAssertEqual(WalletAppearance.colorIndex(for: id, defaults: defaults), 3)
        WalletAppearance.setColorIndex(99, for: id, defaults: defaults)
        XCTAssertNil(WalletAppearance.colorIndex(for: id, defaults: defaults))
    }
}
