import Foundation

struct NetWorth: Equatable {
    let ownWallets: Int64, receivable: Int64, payable: Int64, net: Int64
    static func make(wallets: [Wallet], transactions: [Transaction]) throws -> NetWorth {
        func add(_ a: Int64, _ b: Int64) throws -> Int64 {
            let result = a.addingReportingOverflow(b)
            guard !result.overflow else { throw BalanceCalculator.CalculationError.overflow }
            return result.partialValue
        }
        var own: Int64 = 0, receivable: Int64 = 0, payable: Int64 = 0
        for wallet in wallets {
            let balance = try BalanceCalculator.balance(for: wallet, transactions: transactions, allowMissingCategory: true)
            if !wallet.isPerson { own = try add(own, balance) }
            else if balance >= 0 { receivable = try add(receivable, balance) }
            else {
                guard let magnitude = Int64(exactly: balance.magnitude) else { throw BalanceCalculator.CalculationError.overflow }
                payable = try add(payable, magnitude)
            }
        }
        return Self(ownWallets: own, receivable: receivable, payable: payable, net: try add(add(own, receivable), -payable))
    }
}
