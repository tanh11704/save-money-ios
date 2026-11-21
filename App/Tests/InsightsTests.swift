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
final class InsightsTests: XCTestCase {
    private func local(_ text: String, hour: Int = 0) -> Date {
        ISO8601DateFormatter().date(from: text + String(format: "T%02d:00:00+07:00", hour))!
    }

    private func withDefaults(startDay: Int = 1, _ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "Insights.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let previous = MonthCycle.defaults
        MonthCycle.defaults = defaults
        defer { MonthCycle.defaults = previous; defaults.removePersistentDomain(forName: suite) }
        MonthCycle.startDay = startDay
        try body(defaults)
    }

    private let wallet = Wallet(name: "Tiền mặt", openingBalance: 10_000_000)
    private let food = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
    private let salary = Category(name: "Lương", kind: .income, icon: "banknote")

    private func expense(_ amount: Int64, _ date: Date, category: Category? = nil) -> Transaction {
        Transaction(amount: amount, kind: .expense, date: date, wallet: wallet, category: category ?? food)
    }

    // MARK: Flexible allowance

    func testFlexibleAllowanceSpreadsWhatIsLeftOverRemainingDays() throws {
        try withDefaults { _ in
            let november = try ReportingMonth(year: 2026, month: 11)
            let transactions = [expense(1_000_000, local("2026-11-02", hour: 12)), expense(50_000, local("2026-11-21", hour: 9))]
            // 21/11: 10 days left (21…30). (3.000.000 − 1.000.000) / 10 = 200.000; today spent 50.000.
            let allowance = try XCTUnwrap(StatsService.flexibleAllowance(limit: 3_000_000, month: november, transactions: transactions, now: local("2026-11-21", hour: 15)))
            XCTAssertEqual(allowance.daysLeft, 10)
            XCTAssertEqual(allowance.perDay, 200_000)
            XCTAssertEqual(allowance.spentToday, 50_000)
            XCTAssertEqual(allowance.leftToday, 150_000)
            XCTAssertEqual(allowance.leftInCycle, 1_950_000)
            XCTAssertNil(try StatsService.flexibleAllowance(limit: 3_000_000, month: november, transactions: transactions, now: local("2026-12-01")))
        }
    }

    func testFlexibleAllowanceIsZeroOnceBudgetIsGoneAndFollowsPaydayCycle() throws {
        try withDefaults(startDay: 25) { _ in
            let november = try ReportingMonth(year: 2026, month: 11) // 25/10–24/11
            let over = [expense(3_500_000, local("2026-10-26", hour: 10)), expense(20_000, local("2026-11-24", hour: 8))]
            let allowance = try XCTUnwrap(StatsService.flexibleAllowance(limit: 3_000_000, month: november, transactions: over, now: local("2026-11-24", hour: 20)))
            XCTAssertEqual(allowance.daysLeft, 1)
            XCTAssertEqual(allowance.perDay, 0)
            XCTAssertEqual(allowance.leftToday, -20_000)
            XCTAssertEqual(allowance.leftInCycle, -520_000)
        }
    }

    func testFixedCategoriesAreTakenOutUpFrontInsteadOfSpreadDaily() throws {
        try withDefaults { _ in
            let november = try ReportingMonth(year: 2026, month: 11) // 30 days
            let rent = Category(name: "Nhà ở", kind: .expense, icon: "house"); rent.isFixed = true
            let bills = Category(name: "Hóa đơn", kind: .expense, icon: "doc.text"); bills.isFixed = true
            let fixed = FixedCosts.make(categories: [food, rent, bills, salary], rules: [], month: november)
            XCTAssertEqual(fixed.categoryIDs, [rent.id, bills.id])

            // Payday: paying 4.000.000 rent must not turn today negative. (10.000.000 − 4.000.000) / 30 = 200.000.
            let payday = [expense(4_000_000, local("2026-11-01", hour: 9), category: rent)]
            let first = try XCTUnwrap(StatsService.flexibleAllowance(limit: 10_000_000, month: november, transactions: payday,
                                                                     fixed: fixed, now: local("2026-11-01", hour: 20)))
            XCTAssertEqual(first.fixedSpent, 4_000_000)
            XCTAssertEqual(first.flexibleLimit, 6_000_000)
            XCTAssertEqual(first.perDay, 200_000)
            XCTAssertEqual(first.spentToday, 0)
            XCTAssertEqual(first.leftToday, 200_000)
            // The old behaviour spread the rent over the days and reported today as 3.666.667 over.
            let spread = try XCTUnwrap(StatsService.flexibleAllowance(limit: 10_000_000, month: november, transactions: payday,
                                                                      now: local("2026-11-01", hour: 20)))
            XCTAssertEqual(spread.leftToday, 333_333 - 4_000_000)

            // 21/11: flexible 10.000.000 − 4.500.000 fixed = 5.500.000; − 1.000.000 food before today = 4.500.000 / 10 days.
            let later = payday + [expense(1_000_000, local("2026-11-02", hour: 12)),
                                  expense(500_000, local("2026-11-21", hour: 8), category: bills),
                                  expense(50_000, local("2026-11-21", hour: 9))]
            let allowance = try XCTUnwrap(StatsService.flexibleAllowance(limit: 10_000_000, month: november, transactions: later,
                                                                         fixed: fixed, now: local("2026-11-21", hour: 15)))
            XCTAssertEqual(allowance.fixedSpent, 4_500_000)
            XCTAssertEqual(allowance.fixedReserved, 0)
            XCTAssertEqual(allowance.spentBeforeToday, 1_000_000)
            XCTAssertEqual(allowance.spentToday, 50_000, "the bill paid today is not today's flexible spending")
            XCTAssertEqual(allowance.perDay, 450_000)
            XCTAssertEqual(allowance.leftToday, 400_000)
            XCTAssertEqual(allowance.leftInCycle, 4_450_000)
        }
    }

    func testRecurringExpensesAreFixedAndUpcomingOnesAreReserved() throws {
        try withDefaults { _ in
            let november = try ReportingMonth(year: 2026, month: 11)
            @MainActor func rule(_ amount: Int64, kind: TransactionKind = .expense, start: String, through: String?, paused: Bool = false) -> RecurringRule {
                let rule = RecurringRule()
                rule.amount = amount; rule.kindRaw = kind.rawValue; rule.wallet = wallet
                rule.category = kind == .income ? salary : food
                rule.startDate = local(start); rule.generatedThrough = through.map { local($0) }; rule.isPaused = paused
                return rule
            }
            let internet = rule(300_000, start: "2026-10-05", through: "2026-10-05")      // next: 05/11, still to come
            let gym = rule(200_000, start: "2026-10-01", through: "2026-11-01")           // 01/11 already booked
            let paused = rule(900_000, start: "2026-10-10", through: "2026-10-10", paused: true)
            let pay = rule(9_000_000, kind: .income, start: "2026-10-10", through: "2026-10-10")
            let fixed = FixedCosts.make(categories: [food, salary], rules: [internet, gym, paused, pay], month: november)
            XCTAssertEqual(fixed.planned, [FixedCosts.Planned(date: local("2026-11-05"), amount: 300_000)])

            let booked = expense(200_000, local("2026-11-01"))
            booked.recurrenceKey = RecurrenceCalculator.key(ruleID: gym.id, occurrence: local("2026-11-01"))
            let transactions = [booked, expense(100_000, local("2026-11-02", hour: 12))]
            XCTAssertEqual(try fixed.totals(month: november, transactions: transactions), FixedCosts.Totals(spent: 200_000, reserved: 300_000))
            XCTAssertTrue(fixed.isFixed(booked))
            XCTAssertFalse(FixedCosts.none.isFixed(booked))

            // 03/11: (3.000.000 − 500.000 fixed − 100.000 flexible) / 28 days left.
            let allowance = try XCTUnwrap(StatsService.flexibleAllowance(limit: 3_000_000, month: november, transactions: transactions,
                                                                         fixed: fixed, now: local("2026-11-03", hour: 10)))
            XCTAssertEqual(allowance.fixedSpent, 200_000)
            XCTAssertEqual(allowance.fixedReserved, 300_000)
            XCTAssertEqual(allowance.daysLeft, 28)
            XCTAssertEqual(allowance.perDay, 2_400_000 / 28)

            // Once the generator books 05/11 the reservation moves into spent; the total stays the same.
            internet.generatedThrough = local("2026-11-05")
            XCTAssertTrue(FixedCosts.make(categories: [], rules: [internet], month: november).planned.isEmpty)
        }
    }

    func testFixedCostsAboveTheLimitLeaveNothingToSpreadDaily() throws {
        try withDefaults { _ in
            let november = try ReportingMonth(year: 2026, month: 11)
            let rent = Category(name: "Nhà ở", kind: .expense); rent.isFixed = true
            let fixed = FixedCosts(categoryIDs: [rent.id])
            let allowance = try XCTUnwrap(StatsService.flexibleAllowance(limit: 3_000_000, month: november,
                transactions: [expense(3_500_000, local("2026-11-01"), category: rent), expense(20_000, local("2026-11-10"))],
                fixed: fixed, now: local("2026-11-10", hour: 12)))
            XCTAssertEqual(allowance.flexibleLimit, -500_000)
            XCTAssertEqual(allowance.perDay, 0)
            XCTAssertEqual(allowance.leftToday, -20_000)
            XCTAssertEqual(allowance.leftInCycle, -520_000)
        }
    }

    // MARK: Cycle summary

    func testCycleSummaryAndTrackerShowOncePerFinishedCycle() throws {
        try withDefaults { defaults in
            let october = try ReportingMonth(year: 2026, month: 10)
            let transactions = [
                Transaction(amount: 10_000_000, kind: .income, date: local("2026-10-05", hour: 9), wallet: wallet, category: salary),
                expense(4_000_000, local("2026-10-10", hour: 9)),
                expense(1_000_000, local("2026-09-10", hour: 9))
            ]
            let rules = [BudgetRule(scope: .total, limit: 3_000_000, startMonth: october)]
            let summary = try CycleSummary.make(month: october, transactions: transactions, rules: rules)
            XCTAssertEqual(summary.saved, 6_000_000)
            XCTAssertEqual(summary.savedRateTenths, 600)
            XCTAssertEqual(summary.topExpenses.first?.amount, 4_000_000)
            XCTAssertEqual(summary.overBudget.count, 1)
            XCTAssertEqual(summary.comparison?.expense.previous, 1_000_000)

            let now = local("2026-11-03", hour: 8)
            XCTAssertEqual(CycleSummaryTracker.pending(now: now, transactions: transactions, defaults: defaults), october)
            CycleSummaryTracker.markShown(october, defaults: defaults)
            XCTAssertNil(CycleSummaryTracker.pending(now: now, transactions: transactions, defaults: defaults))
            XCTAssertNil(CycleSummaryTracker.pending(now: local("2026-12-03"), transactions: transactions, defaults: defaults),
                         "No summary for a cycle without transactions")
        }
    }

    // MARK: Widget snapshot

    func testWidgetSnapshotOmitsAmountsUnlessAllowed() throws {
        try withDefaults { _ in
            let november = try ReportingMonth(year: 2026, month: 11)
            let transactions = [expense(1_500_000, local("2026-11-02", hour: 12))]
            let rules = [BudgetRule(scope: .total, limit: 3_000_000, startMonth: november)]
            let now = local("2026-11-21", hour: 15)
            let hidden = WidgetSnapshot.make(transactions: transactions, totalBalance: 8_500_000, rules: rules, showsAmounts: false, now: now)
            XCTAssertEqual(hidden.budgetFraction ?? 0, 0.5, accuracy: 0.0001)
            XCTAssertEqual(hidden.daysLeft, 10)
            XCTAssertNil(hidden.totalBalance); XCTAssertNil(hidden.todayLeft); XCTAssertNil(hidden.cycleSpent)
            let shown = WidgetSnapshot.make(transactions: transactions, totalBalance: 8_500_000, rules: rules, showsAmounts: true, now: now)
            XCTAssertEqual(shown.totalBalance, 8_500_000)
            XCTAssertEqual(shown.todayLeft, 150_000)
            XCTAssertEqual(shown.cycleLimit, 3_000_000)
            XCTAssertTrue(shown.isCurrent(now: now, calendar: LocalCalendar.calendar))
            XCTAssertFalse(shown.isCurrent(now: local("2026-11-22", hour: 1), calendar: LocalCalendar.calendar))
        }
    }

    func testAppGroupIsReadFromProvisioningProfile() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Entitlements</key><dict>\
        <key>com.apple.security.application-groups</key><array><string>group.vn.tanh11704.SaveMoney.ABC123</string></array>\
        </dict></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01, 0x00]) // CMS header bytes around the plist
        data.append(Data(plist.utf8)); data.append(Data([0x00, 0xA0]))
        XCTAssertEqual(SharedContainer.groups(fromProvisioningProfile: data), ["group.vn.tanh11704.SaveMoney.ABC123"])
        XCTAssertEqual(SharedContainer.groups(fromProvisioningProfile: Data("garbage".utf8)), [])
    }

    // MARK: Credit cards

    func testCreditCardStatusPeriodDueDateAndDebt() {
        let card = Wallet(name: "Visa", kind: .card), bank = Wallet(name: "Bank", kind: .bank)
        let settings = CreditCardSettings(limit: 20_000_000, statementDay: 25, dueDay: 10)
        let transactions = [
            Transaction(amount: 2_000_000, kind: .expense, date: local("2026-10-26", hour: 12), wallet: card, category: food),
            Transaction(amount: 500_000, kind: .expense, date: local("2026-10-25", hour: 12), wallet: card, category: food), // previous period
            Transaction(amount: 1_000_000, kind: .transfer, date: local("2026-11-02", hour: 12), wallet: bank, toWallet: card) // payment
        ]
        // 12/11: open period 26/10–25/11; the 25/10 statement is due 10/11 (passed) → next due 10/12.
        let status = CreditCardStatus.make(wallet: card, balance: -1_500_000, settings: settings, transactions: transactions, now: local("2026-11-12", hour: 9))
        XCTAssertEqual(status.debt, 1_500_000)
        XCTAssertEqual(status.available, 18_500_000)
        XCTAssertEqual(status.periodStart, local("2026-10-26"))
        XCTAssertEqual(status.statementDate, local("2026-11-25"))
        XCTAssertEqual(status.spentThisPeriod, 2_000_000)
        XCTAssertEqual(status.dueDate, local("2026-12-10"))
        // 05/11: the 25/10 statement is still due on 10/11.
        let early = CreditCardStatus.make(wallet: card, balance: -1_500_000, settings: settings, transactions: transactions, now: local("2026-11-05", hour: 9))
        XCTAssertEqual(early.dueDate, local("2026-11-10"))
        XCTAssertEqual(early.daysUntilDue, 5)
        // A due day after the statement day falls in the same month; short months clamp.
        let clamped = CreditCardSettings(statementDay: 31, dueDay: 31)
        XCTAssertEqual(CreditCardStatus.dueDate(forStatement: local("2027-01-31"), settings: clamped), local("2027-02-28"))
    }

    func testCreditCardSettingsRoundTripAndRejectInvalid() {
        let suite = "Cards.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        CreditCardSettingsStore.save(CreditCardSettings(limit: 5_000_000, statementDay: 15, dueDay: 5), for: id, defaults: defaults)
        XCTAssertEqual(CreditCardSettingsStore.load(id, defaults: defaults)?.statementDay, 15)
        CreditCardSettingsStore.save(CreditCardSettings(statementDay: 40), for: id, defaults: defaults)
        XCTAssertNil(CreditCardSettingsStore.load(id, defaults: defaults))
    }

    // MARK: Installments

    func testInstallmentProgressFromFiniteRecurringRule() throws {
        let rule = RecurringRule()
        rule.name = "Trả góp iPhone"; rule.amount = 2_000_000; rule.kindRaw = TransactionKind.expense.rawValue
        rule.wallet = wallet; rule.category = food
        rule.startDate = local("2026-01-10")
        rule.endDate = InstallmentProgress.endDate(start: rule.startDate, periods: 12)
        XCTAssertEqual(rule.endDate, local("2026-12-10"))
        rule.generatedThrough = local("2026-03-10")
        let plan = try XCTUnwrap(InstallmentProgress.make(rule))
        XCTAssertEqual(plan.totalPeriods, 12)
        XCTAssertEqual(plan.paidPeriods, 3)
        XCTAssertEqual(plan.remainingPeriods, 9)
        XCTAssertEqual(plan.total, 24_000_000)
        XCTAssertEqual(plan.remaining, 18_000_000)
        XCTAssertEqual(plan.nextDate, local("2026-04-10"))
        XCTAssertFalse(plan.isFinished)

        rule.endDate = nil
        XCTAssertNil(InstallmentProgress.make(rule), "Open-ended recurring rules are not installments")
        XCTAssertNil(InstallmentProgress.endDate(start: Date(), periods: 0))
    }
}
