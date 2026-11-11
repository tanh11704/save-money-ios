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
final class BudgetPersistenceTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        return context
    }
    func testSameMonthUpdatesAndFollowingMonthKeepsHistory() async throws {
        let context = try context()
        let november = try ReportingMonth(year: 2026, month: 11), december = try ReportingMonth(year: 2026, month: 12)
        try BudgetPersistence.setLimit(100, scope: .total, from: november, context: context)
        try BudgetPersistence.setLimit(200, scope: .total, from: november, context: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Budget>()), 1)
        try BudgetPersistence.setLimit(300, scope: .total, from: december, context: context)
        try context.save()
        let rules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: november, rules: rules)?.limit, 200)
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: december, rules: rules)?.limit, 300)
    }
    func testOffThenOnAndIndependentScopes() async throws {
        let context = try context(), month = ReportingMonth()
        let category = Category(name: "Ăn", kind: .expense); context.insert(category)
        try BudgetPersistence.setLimit(100, scope: .category(category.id), from: month, context: context)
        try BudgetPersistence.setLimit(50, scope: .total, from: month, context: context)
        try BudgetPersistence.turnOff(scope: .category(category.id), from: month, context: context)
        try context.save()
        var rules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        XCTAssertNil(BudgetService.activeRule(for: .category(category.id), in: month, rules: rules))
        XCTAssertEqual(BudgetService.activeRule(for: .total, in: month, rules: rules)?.limit, 50)
        try BudgetPersistence.setLimit(200, scope: .category(category.id), from: month, context: context)
        try context.save()
        rules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(BudgetService.activeRule(for: .category(category.id), in: month, rules: rules)?.limit, 200)
    }
    func testInvalidLimitsIncomeAndMissingCategoriesRejected() async throws {
        let context = try context(), month = ReportingMonth()
        let income = Category(name: "Lương", kind: .income); context.insert(income)
        for limit in [Int64(0), -1, MoneyFormatter.maximumInput + 1] {
            XCTAssertThrowsError(try BudgetPersistence.setLimit(limit, scope: .total, from: month, context: context))
        }
        for id in [income.id, UUID()] {
            XCTAssertThrowsError(try BudgetPersistence.setLimit(100, scope: .category(id), from: month, context: context))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Budget>()), 0)
    }
}
