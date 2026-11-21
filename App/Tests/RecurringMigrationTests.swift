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
final class RecurringMigrationTests: XCTestCase {
    func testV2ToV3PreservesLedgerBudgetsAndAddsEmptyRecurringState() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("v2.store"), walletID = UUID(), categoryID = UUID(), transactionID = UUID(), budgetID = UUID()
        func seed() throws {
            let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let wallet = SaveMoneySchemaV2.Wallet(name: "Ví", openingBalance: 1_000); wallet.id = walletID
            let category = SaveMoneySchemaV2.Category(name: "Chi", kind: .expense); category.id = categoryID
            let transaction = SaveMoneySchemaV2.Transaction(amount: 100, kind: .expense, wallet: wallet, category: category); transaction.id = transactionID
            let budget = SaveMoneySchemaV2.Budget(); budget.id = budgetID; budget.category = category
            budget.limit = 500; budget.startYear = 2026; budget.startMonth = 11; budget.isArchived = true
            context.insert(wallet); context.insert(category); context.insert(transaction); context.insert(budget); try context.save()
        }
        try seed()
        let schema = Schema(versionedSchema: SaveMoneySchemaV4.self)
        let container = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container), wallets = try context.fetch(FetchDescriptor<Wallet>()), transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(wallets.map(\.id), [walletID]); XCTAssertEqual(transactions.map(\.id), [transactionID])
        XCTAssertEqual(transactions[0].category?.id, categoryID); XCTAssertNil(transactions[0].recurrenceKey)
        XCTAssertEqual(try BalanceCalculator.balance(for: wallets[0], transactions: transactions), 900)
        let budget = try XCTUnwrap(context.fetch(FetchDescriptor<Budget>()).first)
        XCTAssertEqual(budget.id, budgetID); XCTAssertEqual(budget.limit, 500); XCTAssertTrue(budget.isArchived)
        XCTAssertEqual(budget.category?.id, categoryID); XCTAssertNotNil(budget.rule)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecurringRule>()), 0)
    }

    func testV3ToV4KeepsDataAndMarksSeededRentAndBillsFixed() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("v3.store"), categoryID = UUID(), ruleID = UUID()
        do {
            let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let wallet = SaveMoneySchemaV3.Wallet(name: "Ví", openingBalance: 1_000)
            let category = SaveMoneySchemaV3.Category(name: "Ăn uống", kind: .expense); category.id = categoryID
            let transaction = SaveMoneySchemaV3.Transaction(amount: 100, kind: .expense, wallet: wallet, category: category)
            transaction.recurrenceKey = "\(ruleID.uuidString).20261101"
            let rule = SaveMoneySchemaV3.RecurringRule(); rule.id = ruleID; rule.amount = 100; rule.wallet = wallet; rule.category = category
            context.insert(wallet); context.insert(category); context.insert(transaction); context.insert(rule)
            // Seeded rent/bills (any case, even archived) become fixed; income or other names stay flexible.
            let rent = SaveMoneySchemaV3.Category(name: "Nhà ở", kind: .expense, icon: "house")
            let bills = SaveMoneySchemaV3.Category(name: " hóa đơn ", kind: .expense, icon: "doc.text"); bills.isArchived = true
            let incomeNamedRent = SaveMoneySchemaV3.Category(name: "Nhà ở", kind: .income)
            let other = SaveMoneySchemaV3.Category(name: "Nhà hàng", kind: .expense)
            [rent, bills, incomeNamedRent, other].forEach { context.insert($0) }
            try context.save()
        }
        let schema = Schema(versionedSchema: SaveMoneySchemaV4.self)
        let container = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let category = try XCTUnwrap(categories.first { $0.id == categoryID })
        XCTAssertFalse(category.isFixed)
        XCTAssertEqual(Set(categories.filter(\.isFixed).map { "\($0.kindRaw):\($0.name)" }), ["expense:Nhà ở", "expense: hóa đơn "])
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(transaction.recurrenceKey, "\(ruleID.uuidString).20261101"); XCTAssertEqual(transaction.category?.id, categoryID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecurringRule>()).map(\.id), [ruleID])
    }
}
