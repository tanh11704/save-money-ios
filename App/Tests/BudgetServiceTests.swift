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
final class BudgetServiceTests: XCTestCase {
    @MainActor private final class Fixture {
        let container: ModelContainer
        let a = Wallet(name: "Tiền mặt", openingBalance: 0)
        let b = Wallet(name: "Ngân hàng", openingBalance: 0)
        let food = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
        let travel = Category(name: "Đi lại", kind: .expense, icon: "bus")
        let salary = Category(name: "Lương", kind: .income, icon: "banknote")
        var reader: ModelContext?

        init() throws {
            let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            container.mainContext.autosaveEnabled = false
            [a, b].forEach { container.mainContext.insert($0) }
            [food, travel, salary].forEach { container.mainContext.insert($0) }
            try container.mainContext.save()
        }

        func add(_ amount: Int64, kind: TransactionKind = .expense, category: Category? = nil,
                 date: String = "2026-11-15T12:00:00+07:00") {
            let selected = kind == .transfer ? nil : category ?? (kind == .income ? salary : food)
            container.mainContext.insert(Transaction(amount: amount, kind: kind,
                date: ISO8601DateFormatter().date(from: date)!, wallet: a,
                toWallet: kind == .transfer ? b : nil, category: selected))
        }

        func progress(_ rules: [BudgetRule], month: ReportingMonth) throws -> [BudgetService.Progress] {
            try container.mainContext.save()
            let context = ModelContext(container)
            reader = context
            return try BudgetService.progress(month: month, rules: rules,
                                              transactions: context.fetch(FetchDescriptor<Transaction>()))
        }
    }

    private func month(_ year: Int, _ month: Int) -> ReportingMonth { try! ReportingMonth(year: year, month: month) }
    private var nov: ReportingMonth { month(2026, 11) }

    // MARK: - Active rule

    func testRuleRepeatsEveryMonthAfterStart() {
        let rule = BudgetRule(scope: .total, limit: 5_000_000, startMonth: month(2026, 9))
        XCTAssertNil(BudgetService.activeRule(for: .total, in: month(2026, 8), rules: [rule]))
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month(2026, 9), rules: [rule]), rule)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month(2027, 3), rules: [rule]), rule)
    }

    func testChangingLimitKeepsOldMonthsUnchanged() {
        let old = BudgetRule(scope: .total, limit: 5_000_000, startMonth: month(2026, 9))
        let new = BudgetRule(scope: .total, limit: 7_000_000, startMonth: nov)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month(2026, 10), rules: [new, old])?.limit, 5_000_000)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: nov, rules: [new, old])?.limit, 7_000_000)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month(2026, 12), rules: [new, old])?.limit, 7_000_000)
    }

    func testArchivedRuleTurnsLimitOffFromItsMonthOnly() {
        let old = BudgetRule(scope: .total, limit: 5_000_000, startMonth: month(2026, 9))
        let off = BudgetRule(scope: .total, limit: 5_000_000, startMonth: nov, isArchived: true)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month(2026, 10), rules: [old, off]), old)
        XCTAssertNil(BudgetService.activeRule(for: .total, in: nov, rules: [old, off]))
    }

    func testScopesAreIndependent() {
        let id = UUID()
        let category = BudgetRule(scope: .category(id), limit: 1_000_000, startMonth: nov)
        XCTAssertNil(BudgetService.activeRule(for: .total, in: nov, rules: [category]))
        XCTAssertNil(BudgetService.activeRule(for: .category(UUID()), in: nov, rules: [category]))
        XCTAssertEqual(BudgetService.activeRule(for: .category(id), in: nov, rules: [category]), category)
    }

    // MARK: - Progress

    func testOnlyExpensesCountTowardBudgets() throws {
        let f = try Fixture()
        f.add(300_000)
        f.add(10_000_000, kind: .income)
        f.add(2_000_000, kind: .transfer)
        let rules = [BudgetRule(scope: .total, limit: 1_000_000, startMonth: nov),
                     BudgetRule(scope: .category(f.food.id), limit: 500_000, startMonth: nov)]
        let result = try f.progress(rules, month: nov)
        XCTAssertEqual(result.map(\.spent), [300_000, 300_000])
        XCTAssertEqual(result.first?.scope, .total)
        XCTAssertEqual(result.first?.remaining, 700_000)
    }

    func testTotalBudgetSumsAllExpenseCategories() throws {
        let f = try Fixture()
        f.add(300_000, category: f.food)
        f.add(200_000, category: f.travel)
        let result = try f.progress([BudgetRule(scope: .total, limit: 1_000_000, startMonth: nov)], month: nov)
        XCTAssertEqual(result.first?.spent, 500_000)
        XCTAssertEqual(result.first?.percentageText, "50,0%")
    }

    func testArchivedCategoryExpensesStillCount() throws {
        let f = try Fixture()
        f.add(400_000, category: f.travel)
        f.travel.isArchived = true
        let result = try f.progress([BudgetRule(scope: .category(f.travel.id), limit: 500_000, startMonth: nov)], month: nov)
        XCTAssertEqual(result.first?.spent, 400_000)
        XCTAssertEqual(result.first?.level, .warning)
    }

    func testMonthBoundaryUsesSaigonTime() throws {
        let f = try Fixture()
        f.add(100_000, date: "2026-10-31T23:59:59+07:00")
        f.add(200_000, date: "2026-11-01T00:00:00+07:00")
        f.add(400_000, date: "2026-11-30T23:59:59+07:00")
        f.add(800_000, date: "2026-12-01T00:00:00+07:00")
        let rules = [BudgetRule(scope: .total, limit: 10_000_000, startMonth: month(2026, 1))]
        XCTAssertEqual(try f.progress(rules, month: month(2026, 10)).first?.spent, 100_000)
        XCTAssertEqual(try f.progress(rules, month: nov).first?.spent, 600_000)
        XCTAssertEqual(try f.progress(rules, month: month(2026, 12)).first?.spent, 800_000)
    }

    func testScopeWithoutActiveRuleIsOmittedAndUnusedLimitShowsZero() throws {
        let f = try Fixture()
        let rules = [BudgetRule(scope: .category(f.food.id), limit: 500_000, startMonth: month(2026, 12)),
                     BudgetRule(scope: .category(f.travel.id), limit: 500_000, startMonth: nov)]
        let result = try f.progress(rules, month: nov)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.spent, 0)
        XCTAssertEqual(result.first?.remaining, 500_000)
        XCTAssertEqual(result.first?.level, .normal)
    }

    func testOverspendingGivesNegativeRemaining() throws {
        let p = try BudgetService.progress(scope: .total, limit: 1_000_000, spent: 1_250_000)
        XCTAssertEqual(p.remaining, -250_000)
        XCTAssertEqual(p.level, .over)
        XCTAssertEqual(p.percentageText, "125,0%")
    }

    func testCategoriesSortedByClosestToLimitAfterTotal() throws {
        let f = try Fixture()
        f.add(100_000, category: f.food)
        f.add(450_000, category: f.travel)
        let result = try f.progress([BudgetRule(scope: .category(f.food.id), limit: 1_000_000, startMonth: nov),
                                     BudgetRule(scope: .category(f.travel.id), limit: 500_000, startMonth: nov),
                                     BudgetRule(scope: .total, limit: 9_000_000, startMonth: nov)], month: nov)
        XCTAssertEqual(result.map(\.scope), [.total, .category(f.travel.id), .category(f.food.id)])
    }

    // MARK: - Thresholds

    func testLevelBoundariesAreExact() throws {
        XCTAssertEqual(try BudgetService.level(spent: 799_999, limit: 1_000_000), .normal)
        XCTAssertEqual(try BudgetService.level(spent: 800_000, limit: 1_000_000), .warning)
        XCTAssertEqual(try BudgetService.level(spent: 999_999, limit: 1_000_000), .warning)
        XCTAssertEqual(try BudgetService.level(spent: 1_000_000, limit: 1_000_000), .over)
        // 80% of 3 đồng is 2.4, so 2 is below and 3 reaches it.
        XCTAssertEqual(try BudgetService.level(spent: 2, limit: 3), .normal)
    }

    func testInvalidLimitIsRejected() {
        XCTAssertThrowsError(try BudgetService.level(spent: 0, limit: 0))
        XCTAssertThrowsError(try BudgetService.progress(scope: .total, limit: -1, spent: 0))
    }

    func testHugeAmountsDoNotOverflow() throws {
        let max: Int64 = 999_999_999_999
        let p = try BudgetService.progress(scope: .total, limit: max, spent: Int64.max / 2)
        XCTAssertEqual(p.level, .over)
        XCTAssertEqual(p.percentageText, "999,9%")
        XCTAssertEqual(try BudgetService.level(spent: Int64.max, limit: Int64.max), .over)
        XCTAssertEqual(try BudgetService.level(spent: Int64.max / 100 * 79, limit: Int64.max), .normal)
    }

    func testCrossedThresholdsFireOnlyOnCrossing() throws {
        let limit: Int64 = 1_000_000
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 0, after: 700_000), [])
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 700_000, after: 800_000), [.warning])
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 800_000, after: 900_000), [])
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 700_000, after: 1_200_000), [.warning, .over])
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 1_200_000, after: 1_500_000), [])
        // Deleting or shrinking an expense never fires an alert.
        XCTAssertEqual(try BudgetService.crossedThresholds(limit: limit, before: 1_200_000, after: 100_000), [])
    }
}
