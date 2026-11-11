import Foundation

struct HistoryFilter: Equatable {
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
            let digits = needle.filter { $0.isNumber }
            let moneyQuery = !digits.isEmpty && needle.allSatisfy { $0.isNumber || "., ₫đ".contains($0) }
            if moneyQuery && String(transaction.amount).contains(digits) { return true }
            return needle.isEmpty || [transaction.note, transaction.category?.name ?? "", transaction.wallet?.name ?? "", transaction.toWallet?.name ?? ""].contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) != nil }
        }
    }
    static func flowAccessibilityLabel(for transactions: [Transaction]) -> String {
        guard let total = try? BalanceCalculator.flowTotals(transactions: transactions, allowMissingCategory: true) else { return "Chưa tính được thu chi" }
        return "Thu " + MoneyFormatter.string(from: total.income) + ", chi " + MoneyFormatter.string(from: total.expense)
    }
    static func flowText(for transactions: [Transaction]) -> String? {
        guard let total = try? BalanceCalculator.flowTotals(transactions: transactions, allowMissingCategory: true) else { return nil }
        return (total.income > 0 ? "+" + MoneyFormatter.compact(total.income) + " · " : "") + "−" + MoneyFormatter.compact(total.expense)
    }
    static func expenseText(for transactions: [Transaction]) -> String? {
        guard let total = try? BalanceCalculator.flowTotals(transactions: transactions, allowMissingCategory: true) else { return nil }
        return "−" + MoneyFormatter.string(from: total.expense)
    }
}
