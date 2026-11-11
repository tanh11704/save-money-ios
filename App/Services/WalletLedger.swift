import Foundation

struct WalletLedger {
    static func transactions(for wallet: Wallet, in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { $0.wallet?.id == wallet.id || $0.toWallet?.id == wallet.id }
    }
    static func runningBalances(wallet: Wallet, transactions: [Transaction]) throws -> [Date: Int64] {
        var cumulative: [Transaction] = [], result: [Date: Int64] = [:]
        for day in TransactionGrouping.group(Self.transactions(for: wallet, in: transactions)).reversed() {
            cumulative.append(contentsOf: day.transactions.reversed())
            result[day.date] = try BalanceCalculator.balance(for: wallet, transactions: cumulative, allowMissingCategory: true)
        }
        return result
    }
}
