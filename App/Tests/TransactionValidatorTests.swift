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
final class TransactionValidatorTests: XCTestCase {
    private func draft(kind: TransactionKind = .expense) -> TransactionDraft {
        let wallet = Wallet(name: "A")
        return TransactionDraft(amount: 100, kind: kind, wallet: wallet,
                                toWallet: kind == .transfer ? Wallet(name: "B") : nil,
                                category: kind == .transfer ? nil : Category(name: "Mẫu", kind: kind))
    }

    func testAllKindsValidAtMaximumAmount() async throws {
        for kind in [TransactionKind.income, .expense, .transfer] {
            var input = draft(kind: kind)
            input.amount = MoneyFormatter.maximumInput
            XCTAssertNoThrow(try TransactionValidator.validate(input))
        }
    }

    func testEveryValidationError() async {
        typealias E = TransactionValidator.ValidationError
        var cases: [(TransactionDraft, E)] = []
        func check(_ error: E, kind: TransactionKind = .expense, change: (inout TransactionDraft) -> Void) {
            var input = draft(kind: kind)
            change(&input)
            cases.append((input, error))
        }
        check(.invalidAmount) { $0.amount = 0 }
        check(.invalidAmount) { $0.amount = -1 }
        check(.invalidAmount) { $0.amount = Int64.min }
        check(.amountTooLarge) { $0.amount = MoneyFormatter.maximumInput + 1 }
        for kind in [TransactionKind.income, .expense, .transfer] {
            check(.missingWallet, kind: kind) { $0.wallet = nil }
            check(.archivedWallet, kind: kind) { $0.wallet?.isArchived = true }
        }
        for kind in [TransactionKind.income, .expense] {
            check(.missingCategory, kind: kind) { $0.category = nil }
            check(.unexpectedDestination, kind: kind) { $0.toWallet = Wallet(name: "Thừa") }
            check(.categoryKindMismatch, kind: kind) { $0.category?.kindRaw = kind == .income ? "expense" : "income" }
            check(.archivedCategory, kind: kind) { $0.category?.isArchived = true }
        }
        check(.categoryKindMismatch) { $0.category?.kindRaw = "invalid" }
        check(.missingDestination, kind: .transfer) { $0.toWallet = nil }
        check(.sameWallet, kind: .transfer) { $0.toWallet = $0.wallet }
        check(.unexpectedCategory, kind: .transfer) { $0.category = Category(name: "Thừa", kind: .expense) }
        check(.archivedDestination, kind: .transfer) { $0.toWallet?.isArchived = true }
        XCTAssertEqual(Set(cases.map(\.1)), Set(E.allCases))
        for (input, expected) in cases {
            XCTAssertThrowsError(try TransactionValidator.validate(input)) { XCTAssertEqual($0 as? E, expected) }
        }
        XCTAssertTrue(E.allCases.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    func testArchivedReferencesMayBeRetainedWhileEditing() async throws {
        for kind in [TransactionKind.expense, .income, .transfer] {
            var input = draft(kind: kind)
            let original = Transaction(amount: 100, kind: kind, wallet: input.wallet!, toWallet: input.toWallet, category: input.category)
            input.wallet?.isArchived = true
            input.toWallet?.isArchived = true
            input.category?.isArchived = true
            input.amount = 200
            XCTAssertNoThrow(try TransactionValidator.validate(input, editing: original))
            XCTAssertThrowsError(try TransactionValidator.validate(input))
            input.wallet = Wallet(name: "Ví cũ khác")
            input.wallet?.isArchived = true
            XCTAssertThrowsError(try TransactionValidator.validate(input, editing: original))
        }
    }

    func testEditingCannotSelectDifferentArchivedCategoryOrDestination() async {
        var expense = draft()
        let oldExpense = Transaction(amount: 100, kind: .expense, wallet: expense.wallet!, category: expense.category)
        expense.category = Category(name: "Danh mục lưu trữ khác", kind: .expense)
        expense.category?.isArchived = true
        XCTAssertThrowsError(try TransactionValidator.validate(expense, editing: oldExpense)) {
            XCTAssertEqual($0 as? TransactionValidator.ValidationError, .archivedCategory)
        }
        var transfer = draft(kind: .transfer)
        let oldTransfer = Transaction(amount: 100, kind: .transfer, wallet: transfer.wallet!, toWallet: transfer.toWallet)
        transfer.toWallet = Wallet(name: "Ví nhận lưu trữ khác")
        transfer.toWallet?.isArchived = true
        XCTAssertThrowsError(try TransactionValidator.validate(transfer, editing: oldTransfer)) {
            XCTAssertEqual($0 as? TransactionValidator.ValidationError, .archivedDestination)
        }
    }

    func testChangingKindDropsObsoleteFields() async {
        let expense = draft()
        let transfer = expense.changingKind(to: .transfer)
        XCTAssertNil(transfer.category)
        XCTAssertEqual(transfer.wallet?.id, expense.wallet?.id)
        let income = draft(kind: .transfer).changingKind(to: .income)
        XCTAssertNil(income.toWallet)
        XCTAssertNil(income.category)
        XCTAssertNil(expense.changingKind(to: .income).category)
    }
}
