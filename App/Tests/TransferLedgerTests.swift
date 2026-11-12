import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class TransferLedgerTests: XCTestCase {
    func testPreviewConservesFundsAndAllowsNegativeSource() throws {
        let source = Wallet(name: "Cash"), target = Wallet(name: "Bank")
        let result = try TransferPreview.make(amount: 150, source: source, destination: target, balances: [source.id: 100, target.id: 300])
        XCTAssertEqual(result.sourceAfter, -50)
        XCTAssertEqual(result.destinationAfter, 450)
        XCTAssertEqual(result.sourceAfter + result.destinationAfter, result.sourceBefore + result.destinationBefore)
        XCTAssertTrue(result.sourceGoesNegative)
        XCTAssertThrowsError(try TransferPreview.make(amount: 1, source: source, destination: target, balances: [source.id: .min, target.id: 0]))
        XCTAssertThrowsError(try TransferPreview.make(amount: 1, source: source, destination: target, balances: [source.id: 1, target.id: .max]))
    }
    func testPreviewDeductsFeeFromSourceOnly() throws {
        let source = Wallet(name: "Bank"), target = Wallet(name: "Cash")
        let result = try TransferPreview.make(amount: 500, fee: 3, source: source, destination: target, balances: [source.id: 1_000, target.id: 0])
        XCTAssertEqual(result.sourceAfter, 497)
        XCTAssertEqual(result.destinationAfter, 500)
        XCTAssertThrowsError(try TransferPreview.make(amount: 500, fee: -1, source: source, destination: target, balances: [source.id: 1_000, target.id: 0]))
        XCTAssertThrowsError(try TransferPreview.make(amount: 1, fee: 1, source: source, destination: target, balances: [source.id: .min + 1, target.id: 0]))
    }
    func testLedgerUsesLocalDaysAndIncludesBothTransferDirections() throws {
        let wallet = Wallet(name: "Cash", openingBalance: 1_000), bank = Wallet(name: "Bank")
        let midnight = LocalCalendar.calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let outgoing = Transaction(amount: 200, kind: .transfer, date: midnight.addingTimeInterval(-1), wallet: wallet, toWallet: bank)
        let incoming = Transaction(amount: 50, kind: .transfer, date: midnight, wallet: bank, toWallet: wallet)
        let transactions = [incoming, outgoing]
        let balances = try WalletLedger.runningBalances(wallet: wallet, transactions: transactions)
        XCTAssertEqual(balances[LocalCalendar.calendar.startOfDay(for: outgoing.date)], 800)
        XCTAssertEqual(balances[midnight], 850)
        XCTAssertEqual(balances[midnight], try BalanceCalculator.balance(for: wallet, transactions: transactions))
    }
}
