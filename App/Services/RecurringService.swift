import Foundation
import SwiftData

@MainActor
struct RecurringService {
    struct Result {
        let created: Int
        let skipped: [Skip]
        let hasMore: Bool
    }
    struct Skip: Equatable {
        let ruleID: UUID
        let reason: String
    }
    static func generateDue(now: Date, container: ModelContainer,
                            beforeSave: ((ModelContext) throws -> Void)? = nil) throws -> Result {
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            let rules = try context.fetch(FetchDescriptor<RecurringRule>()).sorted { $0.id.uuidString < $1.id.uuidString }
            var transactions = try context.fetch(FetchDescriptor<Transaction>())
            var keys = Set(transactions.compactMap(\.recurrenceKey))
            var created = 0, skipped: [Skip] = [], hasMore = false
            for rule in rules where !rule.isPaused {
                guard let draft = rule.draft else {
                    skipped.append(Skip(ruleID: rule.id, reason: "\(rule.title): chu kỳ hoặc loại giao dịch không hợp lệ.")); continue
                }
                let dates = RecurrenceCalculator.occurrences(start: rule.startDate, frequency: draft.frequency,
                    interval: rule.interval, end: rule.endDate, after: rule.generatedThrough, through: now, limit: 401)
                guard !dates.isEmpty else { continue }
                do { try RecurringValidator.validate(draft) }
                catch { skipped.append(Skip(ruleID: rule.id, reason: "\(rule.title): \(error.localizedDescription)")); continue }
                hasMore = hasMore || dates.count > 400
                for date in dates.prefix(400) {
                    var transactionDraft = draft.transaction; transactionDraft.date = date
                    try TransactionValidator.validate(transactionDraft)
                    let key = RecurrenceCalculator.key(ruleID: rule.id, occurrence: date)
                    if keys.insert(key).inserted {
                        let transaction = Transaction(amount: rule.amount, kind: transactionDraft.kind, date: date,
                            note: rule.note, wallet: transactionDraft.wallet!, toWallet: transactionDraft.toWallet, category: transactionDraft.category)
                        transaction.recurrenceKey = key; context.insert(transaction); transactions.append(transaction); created += 1
                    }
                    rule.generatedThrough = date
                }
            }
            // A batch must also leave all balances representable as Int64.
            _ = try BalanceCalculator.totalBalance(wallets: context.fetch(FetchDescriptor<Wallet>()), transactions: transactions, allowMissingCategory: true)
            try beforeSave?(context)
            if context.hasChanges { try context.save() }
            return Result(created: created, skipped: skipped, hasMore: hasMore)
        } catch { context.rollback(); throw error }
    }
}
