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
final class ManagementServicesTests: XCTestCase {
    private struct Snapshot {
        let context: ModelContext
        let wallets: [Wallet]
        let categories: [Category]
        let transactions: [Transaction]
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        var wallets: WalletService { WalletService(container: container) }
        var categories: CategoryService { CategoryService(container: container) }
        init() throws {
            let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            container.mainContext.autosaveEnabled = false
        }
        func snapshot() throws -> Snapshot {
            let context = ModelContext(container)
            return Snapshot(context: context, wallets: try context.fetch(FetchDescriptor<Wallet>()),
                            categories: try context.fetch(FetchDescriptor<Category>()),
                            transactions: try context.fetch(FetchDescriptor<Transaction>()))
        }
        func sampleLedger() throws -> (UUID, UUID, UUID, UUID) {
            let a = try wallets.create(WalletDraft(name: "Tiền mặt", openingBalance: 1_000_000))
            let b = try wallets.create(WalletDraft(name: "Ngân hàng", kind: .bank, openingBalance: 2_000_000))
            let c = try categories.create(CategoryDraft(name: "Ăn uống"))
            let s = try snapshot()
            let wallet = try XCTUnwrap(s.wallets.first { $0.id == a })
            let destination = try XCTUnwrap(s.wallets.first { $0.id == b })
            let category = try XCTUnwrap(s.categories.first { $0.id == c })
            let service = TransactionService(container: container)
            let transaction = try service.create(TransactionDraft(amount: 120_000, note: "Mẫu", wallet: wallet, category: category))
            _ = try service.create(TransactionDraft(amount: 300_000, kind: .transfer, wallet: wallet, toWallet: destination))
            return (a, b, c, transaction)
        }
    }

    private func assertError(_ expected: ManagementError, _ body: () throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? ManagementError, expected, file: file, line: line)
        }
    }

    func testWalletDefaultKindAndAllKindsPersist() async throws {
        let f = try Fixture()
        XCTAssertEqual(Wallet(name: "Mặc định").kindRaw, "cash")
        for kind in WalletKind.allCases { try f.wallets.create(WalletDraft(name: kind.title, kind: kind)) }
        let s = try f.snapshot()
        XCTAssertEqual(Set(s.wallets.map(\.kindRaw)), Set(WalletKind.allCases.map(\.rawValue)))
    }

    func testWalletNamesTrimAndRejectCaseInsensitiveArchivedDuplicates() async throws {
        let f = try Fixture()
        let id = try f.wallets.create(WalletDraft(name: "  Tiền mặt \n"))
        _ = try f.wallets.create(WalletDraft(name: "Khác"))
        assertError(.duplicateName) { _ = try f.wallets.create(WalletDraft(name: "TIỀN MẶT")) }
        try f.wallets.archive(id: id)
        assertError(.duplicateName) { _ = try f.wallets.create(WalletDraft(name: "tiền mặt")) }
        let s = try f.snapshot()
        XCTAssertEqual(s.wallets.first { $0.id == id }?.name, "Tiền mặt")
        try f.wallets.update(id: id, with: WalletDraft(name: "TIỀN MẶT", kind: .other))
        try f.wallets.restore(id: id)
        XCTAssertEqual(try f.snapshot().wallets.count, 2)
    }

    func testEmptyLongAndThirtyCharacterNames() async throws {
        let f = try Fixture()
        for name in ["", " \n\t"] {
            assertError(.emptyName) { _ = try f.wallets.create(WalletDraft(name: name)) }
            assertError(.emptyName) { _ = try f.categories.create(CategoryDraft(name: name)) }
        }
        let long = String(repeating: "a", count: 31)
        assertError(.nameTooLong) { _ = try f.wallets.create(WalletDraft(name: long)) }
        assertError(.nameTooLong) { _ = try f.categories.create(CategoryDraft(name: long)) }
        _ = try f.wallets.create(WalletDraft(name: String(repeating: "ế", count: 30)))
        _ = try f.categories.create(CategoryDraft(name: String(repeating: "ế", count: 30)))
    }

    func testCannotArchiveLastActiveWalletIncludingWhenOthersAreArchived() async throws {
        let f = try Fixture()
        let a = try f.wallets.create(WalletDraft(name: "A"))
        assertError(.lastActiveWallet) { try f.wallets.archive(id: a) }
        let b = try f.wallets.create(WalletDraft(name: "B"))
        try f.wallets.archive(id: b)
        try f.wallets.archive(id: b) // Idempotent.
        assertError(.lastActiveWallet) { try f.wallets.archive(id: a) }
        try f.wallets.restore(id: b)
        try f.wallets.archive(id: a)
        let s = try f.snapshot()
        XCTAssertEqual(s.wallets.filter { !$0.isArchived }.map(\.id), [b])
    }

    func testCategoryDuplicatesArePerKindAndIncludeArchived() async throws {
        let f = try Fixture()
        let expense = try f.categories.create(CategoryDraft(name: "  Khác  "))
        _ = try f.categories.create(CategoryDraft(name: "KHÁC", kind: .income))
        assertError(.duplicateName) { _ = try f.categories.create(CategoryDraft(name: "khác")) }
        try f.categories.archive(id: expense)
        assertError(.duplicateName) { _ = try f.categories.create(CategoryDraft(name: "KHÁC")) }
        try f.categories.update(id: expense, with: CategoryDraft(name: "Khác", icon: "gift"))
        try f.categories.restore(id: expense)
        XCTAssertEqual(try f.snapshot().categories.count, 2)
    }

    func testCannotChangeUsedCategoryKindButCanRenameAndChangeIcon() async throws {
        let f = try Fixture()
        let (_, _, categoryID, _) = try f.sampleLedger()
        assertError(.categoryInUse) { try f.categories.update(id: categoryID, with: CategoryDraft(name: "Thu mới", kind: .income)) }
        try f.categories.archive(id: categoryID)
        assertError(.categoryInUse) { try f.categories.update(id: categoryID, with: CategoryDraft(name: "Thu mới", kind: .income)) }
        try f.categories.update(id: categoryID, with: CategoryDraft(name: "Bữa ăn", icon: "fork.knife"))
        let s = try f.snapshot()
        XCTAssertEqual(s.transactions.first { $0.category?.id == categoryID }?.category?.name, "Bữa ăn")
        XCTAssertEqual(s.categories.first { $0.id == categoryID }?.kindRaw, "expense")
    }

    func testUnusedCategoryCanChangeKindButCannotCollideInTargetKind() async throws {
        let f = try Fixture()
        let id = try f.categories.create(CategoryDraft(name: "Khác"))
        _ = try f.categories.create(CategoryDraft(name: "Khác", kind: .income))
        assertError(.duplicateName) { try f.categories.update(id: id, with: CategoryDraft(name: "KHÁC", kind: .income)) }
        try f.categories.update(id: id, with: CategoryDraft(name: "Mới", kind: .income))
        XCTAssertEqual(try f.snapshot().categories.first { $0.id == id }?.kindRaw, "income")
        assertError(.invalidKind) { _ = try f.categories.create(CategoryDraft(name: "Chuyển", kind: .transfer)) }
    }

    func testArchiveRestoreKeepsEveryTransactionAndBalances() async throws {
        let f = try Fixture()
        let (walletID, _, categoryID, expenseID) = try f.sampleLedger()
        let before = try f.snapshot()
        let beforeIDs = Set(before.transactions.map(\.id))
        let expense = try XCTUnwrap(before.transactions.first { $0.id == expenseID })
        let originalDate = expense.date
        try f.wallets.archive(id: walletID)
        try f.categories.archive(id: categoryID)
        let archived = try f.snapshot()
        let wallet = try XCTUnwrap(archived.wallets.first { $0.id == walletID })
        XCTAssertTrue(wallet.isArchived)
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: archived.transactions), 580_000)
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: archived.wallets, transactions: archived.transactions), 2_880_000)
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: archived.transactions).expense, 120_000)
        try f.wallets.restore(id: walletID)
        try f.categories.restore(id: categoryID)
        let after = try f.snapshot()
        XCTAssertEqual(Set(after.transactions.map(\.id)), beforeIDs)
        for original in before.transactions {
            let saved = try XCTUnwrap(after.transactions.first { $0.id == original.id })
            XCTAssertEqual(saved.amount, original.amount)
            XCTAssertEqual(saved.kindRaw, original.kindRaw)
            XCTAssertEqual(saved.date, original.date)
            XCTAssertEqual(saved.note, original.note)
            XCTAssertEqual(saved.wallet?.id, original.wallet?.id)
            XCTAssertEqual(saved.toWallet?.id, original.toWallet?.id)
            XCTAssertEqual(saved.category?.id, original.category?.id)
        }
        let restored = try XCTUnwrap(after.transactions.first { $0.id == expenseID })
        XCTAssertEqual(restored.amount, 120_000)
        XCTAssertEqual(restored.note, "Mẫu")
        XCTAssertEqual(restored.date, originalDate)
        XCTAssertEqual(restored.wallet?.id, walletID)
        XCTAssertEqual(restored.category?.id, categoryID)
        XCTAssertFalse(try XCTUnwrap(after.wallets.first { $0.id == walletID }).isArchived)
        XCTAssertFalse(try XCTUnwrap(after.categories.first { $0.id == categoryID }).isArchived)
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: after.wallets, transactions: after.transactions), 2_880_000)
    }

    func testOpeningBalancePreviewAndEditChangeCurrentBalanceExactly() async throws {
        let f = try Fixture()
        let (id, _, _, _) = try f.sampleLedger()
        let before = try f.snapshot()
        let wallet = try XCTUnwrap(before.wallets.first { $0.id == id })
        let preview = try WalletService.preview(wallet: wallet, openingBalance: -100_000, transactions: before.transactions)
        XCTAssertTrue(preview.hasTransactions)
        XCTAssertEqual(preview.before, 580_000)
        XCTAssertEqual(preview.after, -520_000)
        XCTAssertEqual(wallet.openingBalance, 1_000_000) // Preview never mutates.
        try f.wallets.update(id: id, with: WalletDraft(name: wallet.name, kind: .card, openingBalance: -100_000))
        let after = try f.snapshot()
        XCTAssertEqual(try BalanceCalculator.balance(for: XCTUnwrap(after.wallets.first { $0.id == id }), transactions: after.transactions), -520_000)
        XCTAssertEqual(Set(after.transactions.map(\.id)), Set(before.transactions.map(\.id)))
        XCTAssertEqual(try WalletService.openingBalance(magnitude: 123, isDebt: true), -123)
        XCTAssertEqual(try WalletService.openingBalance(magnitude: 0, isDebt: true), 0)
        assertError(.invalidOpeningBalance) { _ = try WalletService.openingBalance(magnitude: Int64.min, isDebt: true) }
    }

    func testInvalidUpdatesAndMissingIDsLeaveLedgerUntouched() async throws {
        let f = try Fixture()
        let (id, _, categoryID, _) = try f.sampleLedger()
        assertError(.duplicateName) { try f.wallets.update(id: id, with: WalletDraft(name: "NGÂN HÀNG")) }
        assertError(.invalidOpeningBalance) { try f.wallets.update(id: id, with: WalletDraft(name: "Tiền mặt", openingBalance: Int64.min)) }
        assertError(.missingRecord) { try f.wallets.archive(id: UUID()) }
        assertError(.missingRecord) { try f.wallets.restore(id: UUID()) }
        assertError(.missingRecord) { try f.wallets.update(id: UUID(), with: WalletDraft(name: "Mới")) }
        assertError(.missingRecord) { try f.categories.archive(id: UUID()) }
        assertError(.missingRecord) { try f.categories.restore(id: UUID()) }
        assertError(.missingRecord) { try f.categories.update(id: UUID(), with: CategoryDraft(name: "Mới")) }
        assertError(.nameTooLong) { try f.categories.update(id: categoryID, with: CategoryDraft(name: String(repeating: "x", count: 31))) }
        let s = try f.snapshot()
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: s.wallets, transactions: s.transactions), 2_880_000)
        XCTAssertEqual(s.transactions.count, 2)
    }

    func testUnicodeCanonicalNamesMatchButDifferentAccentsRemainDistinct() async throws {
        let f = try Fixture()
        _ = try f.wallets.create(WalletDraft(name: "Café"))
        assertError(.duplicateName) { _ = try f.wallets.create(WalletDraft(name: "CAFE\u{301}")) }
        _ = try f.wallets.create(WalletDraft(name: "Cafe"))
    }
}
