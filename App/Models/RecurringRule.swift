import Foundation
import SwiftData

@Model
final class RecurringRule {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var amount: Int64 = 1
    var note: String = ""
    var wallet: Wallet? = nil
    var toWallet: Wallet? = nil
    var category: Category? = nil
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    var interval: Int = 1
    var startDate: Date = Date()
    var endDate: Date? = nil
    var generatedThrough: Date? = nil
    var isPaused: Bool = false
    var createdAt: Date = Date()
    init() {}
}
