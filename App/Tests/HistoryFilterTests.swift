import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class HistoryFilterTests: XCTestCase {
    func testSearchPeopleWalletsAndFormattedMoney() {
        let own = Wallet(name: "Ngân hàng"), person = Wallet(name: "Lan", kind: .person)
        let transfer = Transaction(amount: 50_000, kind: .transfer, wallet: own, toWallet: person)
        for query in ["lan", "ngan hang", "50000", "50.000 ₫"] {
            XCTAssertEqual(HistoryFilter(query: query).apply(to: [transfer]).map(\.id), [transfer.id])
        }
        XCTAssertTrue(HistoryFilter(query: "Lan 99").apply(to: [transfer]).isEmpty)
    }
    func testSearchAndTransferWalletFilter() {
        let wallet = Wallet(name: "Cash"), destination = Wallet(name: "Bank")
        let category = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
        let expense = Transaction(amount: 50, kind: .expense, note: "Bữa trưa", wallet: wallet, category: category)
        let transfer = Transaction(amount: 30, kind: .transfer, wallet: wallet, toWallet: destination)
        XCTAssertEqual(HistoryFilter(query: "an uong").apply(to: [expense, transfer]).map(\.id), [expense.id])
        XCTAssertEqual(HistoryFilter(query: "TRUA").apply(to: [expense, transfer]).count, 1)
        XCTAssertEqual(HistoryFilter(walletID: destination.id).apply(to: [expense, transfer]).map(\.id), [transfer.id])
        XCTAssertEqual(HistoryFilter.expenseText(for: [expense, transfer]), "−50 ₫")
    }
}
