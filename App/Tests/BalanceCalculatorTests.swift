import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class BalanceCalculatorTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let schema = Schema([Wallet.self, Category.self, Transaction.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testOpeningBalanceWithoutTransactions() async throws {
        let container = try store()
        let wallet = Wallet(name: "Tiền mặt", openingBalance: 500_000)
        container.mainContext.insert(wallet)
        try container.mainContext.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: []), 500_000)
    }

    func testMixedIncomeExpenseAndTransferMatchesHandCalculation() async throws {
        let container = try store()
        let context = container.mainContext
        let cash = Wallet(name: "Tiền mặt", openingBalance: 1_000_000)
        let bank = Wallet(name: "Ngân hàng", openingBalance: 2_000_000)
        let salary = Category(name: "Lương", kind: .income)
        let food = Category(name: "Ăn uống", kind: .expense)
        [cash, bank].forEach { context.insert($0) }
        [salary, food].forEach { context.insert($0) }
        let transactions = [
            Transaction(amount: 500_000, kind: .income, wallet: cash, category: salary),
            Transaction(amount: 120_000, kind: .expense, wallet: cash, category: food),
            Transaction(amount: 300_000, kind: .transfer, wallet: cash, toWallet: bank),
            Transaction(amount: 80_000, kind: .expense, wallet: bank, category: food)
        ]
        transactions.forEach { context.insert($0) }
        try context.save()
        let saved = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(saved.count, 4)
        // Cash: 1,000,000 + 500,000 - 120,000 - 300,000 = 1,080,000.
        // Bank: 2,000,000 + 300,000 - 80,000 = 2,220,000.
        XCTAssertEqual(try BalanceCalculator.balance(for: cash, transactions: saved), 1_080_000)
        XCTAssertEqual(try BalanceCalculator.balance(for: bank, transactions: saved), 2_220_000)
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: [cash, bank], transactions: saved), 3_300_000)
        let totals = try BalanceCalculator.flowTotals(transactions: saved)
        XCTAssertEqual(totals.income, 500_000)
        XCTAssertEqual(totals.expense, 200_000)
        XCTAssertEqual(totals.expenseByCategory, [food.id: 200_000])
    }

    func testTransferPreservesTotalAndDoesNotAffectFlows() async throws {
        let container = try store()
        let source = Wallet(name: "A", openingBalance: 500_000)
        let target = Wallet(name: "B", openingBalance: 200_000)
        container.mainContext.insert(source)
        container.mainContext.insert(target)
        let transfer = Transaction(amount: 150_000, kind: .transfer, wallet: source, toWallet: target)
        container.mainContext.insert(transfer)
        try container.mainContext.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: source, transactions: [transfer]), 350_000)
        XCTAssertEqual(try BalanceCalculator.balance(for: target, transactions: [transfer]), 350_000)
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: [source, target], transactions: [transfer]), 700_000)
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: [transfer]), .init())
    }

    func testArchivedWalletAndCategoryStillCount() async throws {
        let container = try store()
        let wallet = Wallet(name: "Ví cũ", openingBalance: 400_000)
        let category = Category(name: "Danh mục cũ", kind: .expense)
        let transaction = Transaction(amount: 50_000, kind: .expense, wallet: wallet, category: category)
        container.mainContext.insert(wallet)
        container.mainContext.insert(category)
        container.mainContext.insert(transaction)
        wallet.isArchived = true
        category.isArchived = true
        try container.mainContext.save()
        let saved = try container.mainContext.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(saved.first?.wallet?.name, "Ví cũ")
        XCTAssertEqual(saved.first?.category?.name, "Danh mục cũ")
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: [wallet], transactions: saved), 350_000)
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: saved).expenseByCategory, [category.id: 50_000])
    }

    func testLargeIntegerAmountsRemainExactBeyondDoublePrecision() async throws {
        let container = try store()
        let wallet = Wallet(name: "Lớn", openingBalance: 9_007_199_254_740_993)
        let income = Category(name: "Thu", kind: .income)
        let expense = Category(name: "Chi", kind: .expense)
        let transactions = [
            Transaction(amount: 2_000_000_000_001, kind: .income, wallet: wallet, category: income),
            Transaction(amount: 1_000_000_000_000, kind: .expense, wallet: wallet, category: expense)
        ]
        container.mainContext.insert(wallet)
        container.mainContext.insert(income)
        container.mainContext.insert(expense)
        transactions.forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: transactions), 9_008_199_254_740_994)
    }

    func testOverflowThrowsInsteadOfWrappingOrCrashing() async throws {
        let container = try store()
        let wallet = Wallet(name: "Giới hạn", openingBalance: Int64.max)
        let category = Category(name: "Thu", kind: .income)
        container.mainContext.insert(wallet)
        container.mainContext.insert(category)
        let transaction = Transaction(amount: 1, kind: .income, wallet: wallet, category: category)
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        XCTAssertThrowsError(try BalanceCalculator.balance(for: wallet, transactions: [transaction])) {
            XCTAssertEqual($0 as? BalanceCalculator.CalculationError, .overflow)
        }
        XCTAssertThrowsError(try BalanceCalculator.totalBalance(wallets: [wallet, Wallet(name: "Thêm", openingBalance: 1)], transactions: []))
    }

    func testSaigonMonthBoundaryIsHalfOpen() async throws {
        let container = try store()
        let wallet = Wallet(name: "Ví")
        let category = Category(name: "Chi", kind: .expense)
        container.mainContext.insert(wallet)
        container.mainContext.insert(category)
        let transactions = [
            Transaction(amount: 100, kind: .expense, date: date("2026-10-31T23:59:00+07:00"), wallet: wallet, category: category),
            Transaction(amount: 200, kind: .expense, date: date("2026-11-01T00:00:00+07:00"), wallet: wallet, category: category)
        ]
        transactions.forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        let october = LocalCalendar.month(containing: date("2026-10-15T00:00:00+07:00"))
        let november = LocalCalendar.month(containing: date("2026-11-15T00:00:00+07:00"))
        XCTAssertEqual(november.start, date("2026-10-31T17:00:00Z"))
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: transactions, during: october).expense, 100)
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: transactions, during: november).expense, 200)
    }

    func testLeapYearMonthAndEmptyMonth() async throws {
        let container = try store()
        let wallet = Wallet(name: "Ví")
        let category = Category(name: "Thu", kind: .income)
        container.mainContext.insert(wallet)
        container.mainContext.insert(category)
        let transaction = Transaction(amount: 700, kind: .income, date: date("2024-02-29T23:59:00+07:00"), wallet: wallet, category: category)
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        let february = LocalCalendar.month(containing: transaction.date)
        let march = LocalCalendar.month(containing: date("2024-03-01T00:00:00+07:00"))
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: [transaction], during: february).income, 700)
        XCTAssertEqual(try BalanceCalculator.flowTotals(transactions: [transaction], during: march), .init())
    }

    func testInvalidRecordsAreRejected() async throws {
        let container = try store()
        let a = Wallet(name: "A")
        let b = Wallet(name: "B")
        let expense = Category(name: "Chi", kind: .expense)
        container.mainContext.insert(a)
        container.mainContext.insert(b)
        container.mainContext.insert(expense)
        let cases = [
            Transaction(amount: 0, kind: .expense, wallet: a, category: expense),
            Transaction(amount: -1, kind: .expense, wallet: a, category: expense),
            Transaction(amount: Int64.min, kind: .expense, wallet: a, category: expense),
            Transaction(amount: 1, kind: .transfer, wallet: a, toWallet: a),
            Transaction(amount: 1, kind: .transfer, wallet: a),
            Transaction(amount: 1, kind: .transfer, wallet: a, toWallet: b, category: expense),
            Transaction(amount: 1, kind: .income, wallet: a, category: expense),
            Transaction(amount: 1, kind: .expense, wallet: a),
            Transaction(amount: 1, kind: .expense, wallet: a, toWallet: b, category: expense)
        ]
        for transaction in cases {
            container.mainContext.insert(transaction)
            XCTAssertThrowsError(try BalanceCalculator.balance(for: a, transactions: [transaction])) {
                XCTAssertEqual($0 as? BalanceCalculator.CalculationError, .invalidTransaction(transaction.id))
            }
            XCTAssertThrowsError(try BalanceCalculator.flowTotals(transactions: [transaction]))
        }
        let corrupted = Transaction(amount: 1, kind: .expense, wallet: a, category: expense)
        container.mainContext.insert(corrupted)
        corrupted.kindRaw = "unknown"
        XCTAssertThrowsError(try BalanceCalculator.balance(for: a, transactions: [corrupted]))
        corrupted.kindRaw = "expense"
        corrupted.wallet = nil
        XCTAssertThrowsError(try BalanceCalculator.balance(for: a, transactions: [corrupted]))
    }

    func testEditingAndDeletingPersistedTransactionUpdatesBalance() async throws {
        let container = try store()
        let context = container.mainContext
        let wallet = Wallet(name: "Ví", openingBalance: 100_000)
        let category = Category(name: "Chi", kind: .expense)
        context.insert(wallet)
        context.insert(category)
        let transaction = Transaction(amount: 10_000, kind: .expense, wallet: wallet, category: category)
        context.insert(transaction)
        try context.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>())), 90_000)
        transaction.amount = 30_000
        try context.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>())), 70_000)
        context.delete(transaction)
        try context.save()
        XCTAssertEqual(try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>())), 100_000)
    }
}
