import Foundation

/// All arithmetic is in whole VND. Invalid records and overflow must be surfaced,
/// never silently converted into a plausible balance.
struct BalanceCalculator {
    enum CalculationError: Error, Equatable {
        case invalidTransaction(UUID)
        case overflow
    }

    struct FlowTotals: Equatable {
        var income: Int64 = 0
        var expense: Int64 = 0
        var expenseByCategory: [UUID: Int64] = [:]
    }

    static func balance(for wallet: Wallet, transactions: [Transaction]) throws -> Int64 {
        var result = wallet.openingBalance
        for transaction in transactions {
            let kind = try validatedKind(transaction)
            if transaction.wallet?.id == wallet.id {
                result = try add(result, kind == .income ? transaction.amount : -transaction.amount)
            }
            if kind == .transfer, transaction.toWallet?.id == wallet.id {
                result = try add(result, transaction.amount)
            }
        }
        return result
    }

    /// Includes archived wallets. A transfer whose two wallets are included
    /// cancels naturally when the individual balances are added.
    static func totalBalance(wallets: [Wallet], transactions: [Transaction]) throws -> Int64 {
        var total: Int64 = 0
        for wallet in wallets {
            total = try add(total, balance(for: wallet, transactions: transactions))
        }
        return total
    }

    /// The upper date boundary is exclusive, unlike DateInterval.contains.
    /// Archived categories are intentionally retained in the breakdown.
    static func flowTotals(transactions: [Transaction], during interval: DateInterval? = nil) throws -> FlowTotals {
        var totals = FlowTotals()
        for transaction in transactions {
            let kind = try validatedKind(transaction)
            if let interval, !(transaction.date >= interval.start && transaction.date < interval.end) { continue }
            switch kind {
            case .income:
                totals.income = try add(totals.income, transaction.amount)
            case .expense:
                totals.expense = try add(totals.expense, transaction.amount)
                if let categoryID = transaction.category?.id {
                    totals.expenseByCategory[categoryID] = try add(totals.expenseByCategory[categoryID, default: 0], transaction.amount)
                }
            case .transfer:
                break
            }
        }
        return totals
    }

    private static func validatedKind(_ transaction: Transaction) throws -> TransactionKind {
        guard transaction.amount > 0,
              let kind = TransactionKind(rawValue: transaction.kindRaw),
              let wallet = transaction.wallet else {
            throw CalculationError.invalidTransaction(transaction.id)
        }
        switch kind {
        case .transfer:
            guard let destination = transaction.toWallet, destination.id != wallet.id,
                  transaction.category == nil else {
                throw CalculationError.invalidTransaction(transaction.id)
            }
        case .income, .expense:
            guard transaction.toWallet == nil, let category = transaction.category,
                  category.kindRaw == kind.rawValue else {
                throw CalculationError.invalidTransaction(transaction.id)
            }
        }
        return kind
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw CalculationError.overflow }
        return result
    }
}
