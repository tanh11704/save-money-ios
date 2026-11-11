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
final class BudgetMigrationTests: XCTestCase {
    private func migrate(versioned: Bool) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("migration.store")
        let walletID = UUID(), categoryID = UUID(), transactionID = UUID()
        func seed() throws {
            let schema = versioned ? Schema(versionedSchema: SaveMoneySchemaV1.self) : Schema([SaveMoneySchemaV1.Wallet.self, SaveMoneySchemaV1.Category.self, SaveMoneySchemaV1.Transaction.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container); context.autosaveEnabled = false
            let wallet = SaveMoneySchemaV1.Wallet(name: "Ví cũ", openingBalance: 100_000)
            wallet.id = walletID; wallet.isArchived = true
            let category = SaveMoneySchemaV1.Category(name: "Ăn uống", kind: .expense); category.id = categoryID
            let transaction = SaveMoneySchemaV1.Transaction(amount: 20_000, kind: .expense, note: "Giữ nguyên", wallet: wallet, category: category)
            transaction.id = transactionID
            context.insert(wallet); context.insert(category); context.insert(transaction)
            try context.save()
        }
        try seed()
        let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
        let container = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(wallets.map(\.id), [walletID]); XCTAssertTrue(wallets[0].isArchived)
        XCTAssertEqual(categories.map(\.id), [categoryID])
        XCTAssertEqual(transactions.map(\.id), [transactionID]); XCTAssertEqual(transactions[0].note, "Giữ nguyên")
        XCTAssertEqual(transactions[0].wallet?.id, walletID); XCTAssertEqual(transactions[0].category?.id, categoryID)
        XCTAssertEqual(try BalanceCalculator.balance(for: wallets[0], transactions: transactions), 80_000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Budget>()), 0)
        let budget = Budget(); budget.scopeRaw = "total"; budget.limit = 50_000; budget.startYear = 2026; budget.startMonth = 11
        context.insert(budget); try context.save()
        XCTAssertNotNil(budget.rule)
    }
    func testVersionedV1MigrationPreservesLedger() async throws { try migrate(versioned: true) }
    func testOriginalUnversionedStoreMigrationPreservesLedger() async throws { try migrate(versioned: false) }
    func testInvalidBudgetNeverBecomesTotal() async throws {
        let budget = Budget(); budget.limit = 1; budget.startYear = 2026; budget.startMonth = 11
        XCTAssertNil(budget.rule)
        budget.scopeRaw = "total"; XCTAssertNotNil(budget.rule)
        budget.startMonth = 13; XCTAssertNil(budget.rule)
        budget.startMonth = 11; budget.limit = 0; XCTAssertNil(budget.rule)
    }
    func testFreshVersionedStoreCanReopenWithMigrationPlan() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("fresh.store"), cloudKitDatabase: .none)
        func create() throws {
            let container = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self, configurations: [configuration])
            let context = ModelContext(container)
            let budget = Budget(); budget.scopeRaw = "total"; budget.limit = 100
            budget.startYear = 2026; budget.startMonth = 11
            context.insert(budget); try context.save()
        }
        try create()
        let reopened = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self, configurations: [configuration])
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<Budget>()).first?.limit, 100)
    }

}
