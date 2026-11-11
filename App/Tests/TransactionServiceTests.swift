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
final class TransactionServiceTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let a: Wallet
        let b: Wallet
        let income: Category
        let expense: Category
        var service: TransactionService { TransactionService(container: container) }

        func draft(_ kind: TransactionKind, amount: Int64 = 100) -> TransactionDraft {
            TransactionDraft(amount: amount, kind: kind, wallet: a,
                             toWallet: kind == .transfer ? b : nil,
                             category: kind == .transfer ? nil : kind == .income ? income : expense)
        }

        func transactions() throws -> [Transaction] {
            try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        }

        func balance(_ name: String) throws -> Int64 {
            let context = ModelContext(container)
            let wallet = try XCTUnwrap(context.fetch(FetchDescriptor<Wallet>()).first { $0.name == name })
            return try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>()))
        }
    }

    private func fixture() throws -> Fixture {
        let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        container.mainContext.autosaveEnabled = false
        let a = Wallet(name: "A", openingBalance: 1_000)
        let b = Wallet(name: "B", openingBalance: 2_000)
        let income = Category(name: "Thu", kind: .income)
        let expense = Category(name: "Chi", kind: .expense)
        container.mainContext.insert(a)
        container.mainContext.insert(b)
        container.mainContext.insert(income)
        container.mainContext.insert(expense)
        try container.mainContext.save()
        return Fixture(container: container, a: a, b: b, income: income, expense: expense)
    }

    func testBalancesAfterCreateEditChangeKindAndDelete() async throws {
        let f = try fixture()
        let service = f.service
        let id = try service.create(f.draft(.expense))
        XCTAssertEqual(try f.balance("A"), 900)
        var transfer = f.draft(.transfer, amount: 300)
        transfer.category = f.expense // Obsolete form field must be cleared.
        try service.update(id: id, with: transfer)
        XCTAssertEqual(try f.balance("A"), 700)
        XCTAssertEqual(try f.balance("B"), 2_300)
        XCTAssertNil(try f.transactions().first?.category)
        var income = f.draft(.income, amount: 200)
        income.toWallet = f.b // Obsolete destination must be cleared.
        income.note = "Đã sửa"
        income.date = Date(timeIntervalSince1970: 123)
        try service.update(id: id, with: income)
        XCTAssertEqual(try f.balance("A"), 1_200)
        XCTAssertEqual(try f.balance("B"), 2_000)
        let saved = try XCTUnwrap(f.transactions().first)
        XCTAssertEqual(saved.id, id)
        XCTAssertNil(saved.toWallet)
        XCTAssertEqual(saved.category?.id, f.income.id)
        XCTAssertEqual(saved.note, income.note)
        XCTAssertEqual(saved.date, income.date)
        try service.delete(id: id)
        XCTAssertTrue(try f.transactions().isEmpty)
        XCTAssertEqual(try f.balance("A"), 1_000)
        XCTAssertEqual(try f.balance("B"), 2_000)
    }

    func testEveryKindTransitionCleansObsoleteFields() async throws {
        let f = try fixture()
        let service = f.service
        for source in [TransactionKind.expense, .income, .transfer] {
            for target in [TransactionKind.expense, .income, .transfer] {
                let id = try service.create(f.draft(source))
                var edited = f.draft(target)
                if target != source {
                    if target == .transfer { edited.category = f.expense }
                    else { edited.toWallet = f.b }
                }
                try service.update(id: id, with: edited)
                let saved = try XCTUnwrap(f.transactions().first { $0.id == id })
                XCTAssertEqual(saved.kindRaw, target.rawValue)
                if target == .transfer {
                    XCTAssertNil(saved.category)
                    XCTAssertEqual(saved.toWallet?.id, f.b.id)
                } else {
                    XCTAssertNil(saved.toWallet)
                    XCTAssertEqual(saved.category?.kindRaw, target.rawValue)
                }
                try service.delete(id: id)
            }
        }
    }

    func testInvalidCreateAndEditPreserveStoredData() async throws {
        let f = try fixture()
        let service = f.service
        var invalid = f.draft(.expense)
        invalid.amount = 0
        XCTAssertThrowsError(try service.create(invalid))
        XCTAssertTrue(try f.transactions().isEmpty)
        var invalidTransfer = f.draft(.transfer)
        invalidTransfer.category = f.expense
        XCTAssertThrowsError(try service.create(invalidTransfer))
        let id = try service.create(f.draft(.expense))
        XCTAssertThrowsError(try service.update(id: id, with: invalid))
        XCTAssertEqual(try f.transactions().first?.amount, 100)
        XCTAssertEqual(try f.balance("A"), 900)
        XCTAssertThrowsError(try service.update(id: UUID(), with: f.draft(.income)))
        XCTAssertThrowsError(try service.delete(id: UUID()))
        var unpersisted = f.draft(.expense)
        unpersisted.wallet = Wallet(name: "Chưa lưu")
        XCTAssertThrowsError(try service.create(unpersisted))
        XCTAssertEqual(try f.transactions().count, 1)
    }

    func testArchiveChangesAreRecheckedAndOldReferencesMayBeRetained() async throws {
        let f = try fixture()
        let service = f.service
        let id = try service.create(f.draft(.expense))
        f.a.isArchived = true
        f.expense.isArchived = true
        try f.container.mainContext.save()
        XCTAssertThrowsError(try service.create(f.draft(.expense)))
        try service.update(id: id, with: f.draft(.expense, amount: 200))
        XCTAssertEqual(try f.balance("A"), 800)
    }

    func testOperationDoesNotSaveOrRollbackUnrelatedMainContextChanges() async throws {
        let f = try fixture()
        f.a.name = "Chưa lưu"
        var invalid = f.draft(.expense)
        invalid.amount = 0
        XCTAssertThrowsError(try f.service.create(invalid))
        XCTAssertEqual(f.a.name, "Chưa lưu")
        XCTAssertEqual(try ModelContext(f.container).fetch(FetchDescriptor<Wallet>()).first { $0.id == f.a.id }?.name, "A")
        _ = try f.service.create(f.draft(.expense))
        XCTAssertEqual(try ModelContext(f.container).fetch(FetchDescriptor<Wallet>()).first { $0.id == f.a.id }?.name, "A")
    }

    func testRecentSelectionChangesOnlyAfterSuccessfulSave() async throws {
        let f = try fixture()
        let suite = "SaveMoneyServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recent = RecentSelectionStore(defaults: defaults)
        let service = TransactionService(container: f.container, recentSelections: recent)
        var invalid = f.draft(.expense)
        invalid.amount = 0
        XCTAssertThrowsError(try service.create(invalid))
        XCTAssertNil(recent.selection(for: .expense, wallets: [f.a], categories: [f.expense]).walletID)
        let id = try service.create(f.draft(.expense))
        XCTAssertEqual(recent.selection(for: .expense, wallets: [f.a], categories: [f.expense]).walletID, f.a.id)
        try service.update(id: id, with: f.draft(.transfer))
        let selection = recent.selection(for: .transfer, wallets: [f.a, f.b], categories: [])
        XCTAssertEqual(selection.walletID, f.a.id)
        XCTAssertEqual(selection.destinationID, f.b.id)
        XCTAssertNil(selection.categoryID)
    }
}
