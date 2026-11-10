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
final class RecentSelectionStoreTests: XCTestCase {
    func testPersistsIDsPerKindAndFiltersUnavailableSelections() async throws {
        let suite = "SaveMoneyRecentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = Wallet(name: "A")
        let b = Wallet(name: "B")
        let income = Category(name: "Thu", kind: .income)
        let expense = Category(name: "Chi", kind: .expense)
        let store = RecentSelectionStore(defaults: defaults)
        XCTAssertEqual(store.selection(for: .expense, wallets: [], categories: []), .init())
        store.remember(TransactionDraft(amount: 1, kind: .expense, wallet: a, category: expense))
        store.remember(TransactionDraft(amount: 1, kind: .income, wallet: b, category: income))
        store.remember(TransactionDraft(amount: 1, kind: .transfer, wallet: a, toWallet: b))
        let reopened = RecentSelectionStore(defaults: defaults)
        XCTAssertEqual(reopened.selection(for: .expense, wallets: [a, b], categories: [expense, income]), .init(walletID: a.id, categoryID: expense.id))
        XCTAssertEqual(reopened.selection(for: .income, wallets: [a, b], categories: [expense, income]), .init(walletID: b.id, categoryID: income.id))
        XCTAssertEqual(reopened.selection(for: .transfer, wallets: [a, b], categories: []), .init(walletID: a.id, destinationID: b.id))
        a.isArchived = true
        b.isArchived = true
        expense.isArchived = true
        XCTAssertEqual(reopened.selection(for: .expense, wallets: [a, b], categories: [expense]), .init())
        XCTAssertEqual(reopened.selection(for: .transfer, wallets: [a, b], categories: []), .init())
        XCTAssertEqual(reopened.selection(for: .income, wallets: [], categories: []), .init())
        b.isArchived = false
        income.kindRaw = "expense"
        XCTAssertNil(reopened.selection(for: .income, wallets: [b], categories: [income]).categoryID)
    }

    func testClearingSelectionAndInvalidDefaultsAreSafe() async throws {
        let suite = "SaveMoneyRecentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSelectionStore(defaults: defaults)
        let wallet = Wallet(name: "Ví")
        store.remember(TransactionDraft(amount: 1, wallet: wallet, category: Category(name: "Chi", kind: .expense)))
        store.remember(TransactionDraft())
        XCTAssertEqual(store.selection(for: .expense, wallets: [wallet], categories: []), .init())
        defaults.set("not-a-uuid", forKey: "SaveMoney.recentSelection.expense.wallet")
        XCTAssertNil(store.selection(for: .expense, wallets: [wallet], categories: []).walletID)
    }
}
