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
}
