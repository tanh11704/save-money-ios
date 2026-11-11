import Foundation

struct HistoryFilter {
    var query = ""
    var walletID: UUID?
    var categoryID: UUID?
    var month: ReportingMonth?

    func apply(to transactions: [Transaction]) -> [Transaction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { transaction in
            if let walletID, transaction.wallet?.id != walletID && transaction.toWallet?.id != walletID { return false }
            if let categoryID, transaction.category?.id != categoryID { return false }
            if let month, !month.interval.contains(transaction.date) || transaction.date == month.interval.end { return false }
            return needle.isEmpty || [transaction.note, transaction.category?.name ?? ""].contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) != nil }
        }
    }
    static func expenseText(for transactions: [Transaction]) -> String? {
        guard let total = try? BalanceCalculator.flowTotals(transactions: transactions, allowMissingCategory: true) else { return nil }
        return "−" + MoneyFormatter.string(from: total.expense)
    }
}
