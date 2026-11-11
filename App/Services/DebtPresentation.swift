import Foundation

struct DebtPresentation {
    enum Action: String, Identifiable { case lend, collect, borrow, repay; var id: String { rawValue } }
    struct Label: Equatable { let title: String; let detail: String?; let balanceAfter: Int64 }
    static func title(_ action: Action, person: Wallet) -> String {
        switch action {
        case .lend: return "Cho \(person.name) vay"
        case .collect: return "\(person.name) trả tiền"
        case .borrow: return "Vay \(person.name)"
        case .repay: return "Trả nợ \(person.name)"
        }
    }
    static func labels(transactions: [Transaction]) throws -> [UUID: Label] {
        let ordered = transactions.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var balances: [UUID: Int64] = [:], result: [UUID: Label] = [:]
        for transaction in ordered {
            guard let person = transaction.wallet?.isPerson == true ? transaction.wallet : transaction.toWallet?.isPerson == true ? transaction.toWallet : nil else { continue }
            let before = balances[person.id] ?? person.openingBalance
            let after = try BalanceCalculator.balance(for: person, transactions: [transaction], openingBalance: before, allowMissingCategory: true)
            balances[person.id] = after
            let title: String
            if transaction.kindRaw == "expense" { title = "\(person.name) trả hộ · \(transaction.category?.name ?? "Chi tiêu")" }
            else if transaction.toWallet?.id == person.id { title = before < 0 ? "Trả nợ \(person.name)" : "Cho \(person.name) vay" }
            else { title = before > 0 ? "\(person.name) trả nợ" : "Vay \(person.name)" }
            let detail: String?
            if before > 0 && after < 0 { detail = "Dư \(MoneyFormatter.string(from: after).replacingOccurrences(of: "−", with: "")) thành bạn nợ \(person.name)" }
            else if before < 0 && after > 0 { detail = "Dư \(MoneyFormatter.string(from: after)) thành \(person.name) nợ bạn" }
            else { detail = nil }
            result[transaction.id] = Label(title: title, detail: detail, balanceAfter: after)
        }
        return result
    }
    static func directionText(_ balance: Int64, person: Wallet) -> String {
        balance == 0 ? "Đã xong" : balance > 0 ? "\(person.name) đang nợ bạn" : "Bạn đang nợ \(person.name)"
    }
    static func balanceText(_ balance: Int64, person: Wallet) -> String {
        if balance == 0 { return "Đã xong" }
        let amount = MoneyFormatter.string(from: balance).replacingOccurrences(of: "−", with: "")
        return balance > 0 ? "\(person.name) đang nợ bạn \(amount)" : "Bạn đang nợ \(person.name) \(amount)"
    }
    static func summary(person: Wallet, transactions: [Transaction]) throws -> String {
        let balance = try BalanceCalculator.balance(for: person, transactions: transactions, allowMissingCategory: true)
        let labels = try labels(transactions: transactions)
        let lines = WalletLedger.transactions(for: person, in: transactions).sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }.map {
            "\(TransactionPresentation.shortDate($0.date)): \(labels[$0.id]?.title ?? "Giao dịch") · \(MoneyFormatter.string(from: $0.amount))"
        }
        return ([balanceText(balance, person: person)] + lines).joined(separator: "\n")
    }
}
