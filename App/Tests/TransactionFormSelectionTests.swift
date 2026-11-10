import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class TransactionFormSelectionTests: XCTestCase {
    func testNewFormUsesRecentPerKindAndNeverArchivedReferences() async throws {
        let suite = "FormSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recent = RecentSelectionStore(defaults: defaults)
        let a = Wallet(name: "A")
        let b = Wallet(name: "B")
        let expense = Category(name: "Chi", kind: .expense)
        let salary = Category(name: "Thu", kind: .income)
        recent.remember(TransactionDraft(amount: 1, kind: .income, wallet: b, category: salary))
        let draft = TransactionFormSelection.restoring(TransactionDraft(kind: .income), wallets: [a, b], categories: [expense, salary], recent: recent)
        XCTAssertEqual(draft.wallet?.id, b.id)
        XCTAssertEqual(draft.category?.id, salary.id)
        b.isArchived = true
        salary.isArchived = true
        let next = TransactionFormSelection.restoring(draft, wallets: [a, b], categories: [expense, salary], recent: recent)
        XCTAssertEqual(next.wallet?.id, a.id)
        XCTAssertNil(next.category)
    }

    func testArchivedReferencesOnlyAppearInTheirOriginalRole() async {
        let a = Wallet(name: "Cũ")
        let b = Wallet(name: "Mới")
        a.isArchived = true
        XCTAssertEqual(TransactionFormSelection.wallets([a, b]).map(\.id), [b.id])
        XCTAssertEqual(TransactionFormSelection.wallets([a, b], retaining: a.id).count, 2)
        XCTAssertEqual(TransactionFormSelection.wallets([a, b], retaining: a.id, excluding: a.id).map(\.id), [b.id])
        let archived = Category(name: "Cũ", kind: .expense)
        let income = Category(name: "Thu", kind: .income)
        archived.isArchived = true
        XCTAssertTrue(TransactionFormSelection.categories([archived, income], kind: .expense).isEmpty)
        XCTAssertEqual(TransactionFormSelection.categories([archived, income], kind: .expense, retaining: archived.id).map(\.id), [archived.id])
        XCTAssertTrue(TransactionFormSelection.categories([archived, income], kind: .transfer).isEmpty)
    }

    func testChangingSourceNeverLeavesSameDestination() async {
        let a = Wallet(name: "A")
        let b = Wallet(name: "B")
        let input = TransactionDraft(amount: 100, kind: .transfer, wallet: a, toWallet: b)
        let result = TransactionFormSelection.selectingWallet(b, in: input, available: [a, b])
        XCTAssertEqual(result.wallet?.id, b.id)
        XCTAssertEqual(result.toWallet?.id, a.id)
        let noDestination = TransactionFormSelection.selectingWallet(b, in: input, available: [b])
        XCTAssertNil(noDestination.toWallet)
    }

    func testRecentCategoryComesFirstAndSignsRemainExplicit() async {
        let a = Category(name: "Ăn uống", kind: .expense)
        let b = Category(name: "Đi lại", kind: .expense)
        XCTAssertEqual(TransactionFormSelection.categories([a, b], kind: .expense, recentID: b.id).first?.id, b.id)
        let wallet = Wallet(name: "Ví")
        for (kind, sign) in [(TransactionKind.income, "+"), (.expense, "−"), (.transfer, "")] {
            let transaction = Transaction(amount: 1_000, kind: kind, wallet: wallet)
            XCTAssertEqual(TransactionPresentation.amount(transaction), sign + "1.000 ₫")
        }
    }
    func testArchiveReconciliationClearsNewFormButKeepsHistoricalEdit() async throws {
        let wallet = Wallet(name: "Ví")
        let category = Category(name: "Chi", kind: .expense)
        let original = Transaction(amount: 100, kind: .expense, wallet: wallet, category: category)
        let input = TransactionDraft(amount: 200, wallet: wallet, category: category)
        wallet.isArchived = true
        category.isArchived = true
        let newForm = TransactionFormSelection.reconcile(input, wallets: [wallet], categories: [category])
        XCTAssertNil(newForm.wallet)
        XCTAssertNil(newForm.category)
        XCTAssertEqual(newForm.amount, 200)
        let edit = TransactionFormSelection.reconcile(input, wallets: [wallet], categories: [category], editing: original)
        XCTAssertEqual(edit.wallet?.id, wallet.id)
        XCTAssertEqual(edit.category?.id, category.id)
        XCTAssertNoThrow(try TransactionValidator.validate(edit, editing: original))
        let missing = TransactionFormSelection.reconcile(input, wallets: [], categories: [])
        XCTAssertNil(missing.wallet)
        XCTAssertNil(missing.category)
    }

    func testNoActiveWalletAndArchivedRecentSelectionAreSafe() async throws {
        let suite = "FormSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recent = RecentSelectionStore(defaults: defaults)
        let wallet = Wallet(name: "Cũ")
        let category = Category(name: "Cũ", kind: .expense)
        recent.remember(TransactionDraft(amount: 1, wallet: wallet, category: category))
        wallet.isArchived = true
        category.isArchived = true
        let restored = TransactionFormSelection.restoring(TransactionDraft(), wallets: [wallet], categories: [category], recent: recent)
        XCTAssertNil(restored.wallet)
        XCTAssertNil(restored.category)
        XCTAssertThrowsError(try TransactionValidator.validate(restored))
        let reopened = RecentSelectionStore(defaults: defaults)
        XCTAssertNil(reopened.selection(for: .expense, wallets: [wallet], categories: [category]).walletID)
        XCTAssertNil(reopened.selection(for: .expense, wallets: [wallet], categories: [category]).categoryID)
    }

}
