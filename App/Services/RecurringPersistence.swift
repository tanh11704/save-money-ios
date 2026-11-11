import Foundation
import SwiftData

struct RecurringDraft {
    var name = ""
    var transaction = TransactionDraft()
    var frequency: RecurrenceFrequency = .monthly
    var interval = 1
    var startDate = Date()
    var endDate: Date?
}

struct RecurringValidator {
    enum ValidationError: LocalizedError {
        case interval, dates, name, frequency
        var errorDescription: String? {
            switch self {
            case .interval: return "Chu kỳ phải từ 1 trở lên."
            case .dates: return "Ngày kết thúc không được trước ngày bắt đầu."
            case .name: return "Tên giao dịch định kỳ tối đa 60 ký tự."
            case .frequency: return "Chu kỳ không hợp lệ."
            }
        }
    }
    static func validate(_ draft: RecurringDraft) throws {
        guard draft.interval >= 1 else { throw ValidationError.interval }
        guard draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count <= 60 else { throw ValidationError.name }
        if let end = draft.endDate, LocalCalendar.calendar.startOfDay(for: end) < LocalCalendar.calendar.startOfDay(for: draft.startDate) { throw ValidationError.dates }
        try TransactionValidator.validate(draft.transaction)
    }
}

extension RecurringRule {
    var title: String { name.isEmpty ? category?.name ?? "Chuyển tiền" : name }
    var draft: RecurringDraft? {
        guard let kind = TransactionKind(rawValue: kindRaw), let frequency = RecurrenceFrequency(rawValue: frequencyRaw) else { return nil }
        return RecurringDraft(name: name, transaction: TransactionDraft(amount: amount, kind: kind, note: note,
            wallet: wallet, toWallet: toWallet, category: category), frequency: frequency, interval: interval, startDate: startDate, endDate: endDate)
    }
}

@MainActor
struct RecurringPersistence {
    let container: ModelContainer
    func save(_ input: RecurringDraft, editing id: UUID? = nil) throws {
        try ManagementPersistence(container: container).write { context in
            var draft = input
            let wallets = try context.fetch(FetchDescriptor<Wallet>()), categories = try context.fetch(FetchDescriptor<Category>())
            draft.transaction.wallet = wallets.first { $0.id == input.transaction.wallet?.id }
            draft.transaction.toWallet = wallets.first { $0.id == input.transaction.toWallet?.id }
            draft.transaction.category = categories.first { $0.id == input.transaction.category?.id }
            try RecurringValidator.validate(draft)
            let rule: RecurringRule
            if let id {
                guard let existing = try context.fetch(FetchDescriptor<RecurringRule>()).first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
                rule = existing // Preserve the cursor even when changing the anchor/frequency.
            } else { rule = RecurringRule(); context.insert(rule) }
            rule.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.kindRaw = draft.transaction.kind.rawValue; rule.amount = draft.transaction.amount; rule.note = draft.transaction.note
            rule.wallet = draft.transaction.wallet; rule.toWallet = draft.transaction.toWallet; rule.category = draft.transaction.category
            rule.frequencyRaw = draft.frequency.rawValue; rule.interval = draft.interval
            rule.startDate = LocalCalendar.calendar.startOfDay(for: draft.startDate)
            rule.endDate = draft.endDate.map { LocalCalendar.calendar.startOfDay(for: $0) }
        }
        NotificationCenter.default.post(name: .recurringRulesDidChange, object: container)
    }
    func setPaused(_ paused: Bool, id: UUID) throws {
        try ManagementPersistence(container: container).write { context in
            guard let rule = try context.fetch(FetchDescriptor<RecurringRule>()).first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
            rule.isPaused = paused
        }
        NotificationCenter.default.post(name: .recurringRulesDidChange, object: container)
    }
}
