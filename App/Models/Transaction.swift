import Foundation
import SwiftData

enum TransactionKind: String, Codable {
    case income, expense, transfer
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var amount: Int64 = 1
    var kindRaw: String = TransactionKind.expense.rawValue
    var date: Date = Date()
    var recurrenceKey: String? = nil
    var note: String = ""
    var wallet: Wallet?
    var toWallet: Wallet?
    var category: Category?

    init(amount: Int64, kind: TransactionKind, date: Date = Date(), note: String = "",
         wallet: Wallet, toWallet: Wallet? = nil, category: Category? = nil) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.wallet = wallet
        self.toWallet = toWallet
        self.category = category
    }
}
