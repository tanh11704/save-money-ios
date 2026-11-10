import Foundation
import SwiftData

/// Owns a non-autosaving context: a failed save rolls back only this operation.
/// IDs are resolved again here so stale UI objects cannot bypass archive validation.
@MainActor
final class TransactionService {
    enum ServiceError: LocalizedError {
        case missingRecord
        var errorDescription: String? { "Dữ liệu không còn tồn tại. Hãy tải lại và thử lại." }
    }

    private let container: ModelContainer
    private var context: ModelContext
    private let recentSelections: RecentSelectionStore?

    init(container: ModelContainer, recentSelections: RecentSelectionStore? = nil) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.recentSelections = recentSelections
    }

    @discardableResult
    func create(_ input: TransactionDraft) throws -> UUID {
        try perform {
            let draft = try resolve(input)
            try TransactionValidator.validate(draft)
            guard let wallet = draft.wallet else { throw TransactionValidator.ValidationError.missingWallet }
            let transaction = Transaction(amount: draft.amount, kind: draft.kind, date: draft.date,
                                          note: draft.note, wallet: wallet, toWallet: draft.toWallet, category: draft.category)
            context.insert(transaction)
            try context.save()
            recentSelections?.remember(draft)
            return transaction.id
        }
    }

    func update(id: UUID, with input: TransactionDraft) throws {
        try perform {
            let transaction = try find(id)
            let cleaned = transaction.kindRaw != input.kind.rawValue ? input.normalized : input
            let draft = try resolve(cleaned)
            try TransactionValidator.validate(draft, editing: transaction)
            transaction.amount = draft.amount
            transaction.kindRaw = draft.kind.rawValue
            transaction.date = draft.date
            transaction.note = draft.note
            transaction.wallet = draft.wallet
            transaction.toWallet = draft.toWallet
            transaction.category = draft.category
            try context.save()
            recentSelections?.remember(draft)
        }
    }

    func delete(id: UUID) throws {
        try perform {
            context.delete(try find(id))
            try context.save()
        }
    }

    private func perform<T>(_ operation: () throws -> T) throws -> T {
        // Fresh identity map on each call: archive changes made elsewhere are visible.
        context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try operation()
            NotificationCenter.default.post(name: .ledgerDidChange, object: container, userInfo: ["transaction": true])
            return result
        }
        catch { context.rollback(); throw error }
    }

    private func find(_ id: UUID) throws -> Transaction {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        guard let transaction = try context.fetch(descriptor).first else { throw ServiceError.missingRecord }
        return transaction
    }

    private func resolve(_ input: TransactionDraft) throws -> TransactionDraft {
        var draft = input
        if let id = input.wallet?.id { draft.wallet = try wallet(id) }
        if let id = input.toWallet?.id { draft.toWallet = try wallet(id) }
        if let id = input.category?.id {
            let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
            guard let category = try context.fetch(descriptor).first else { throw ServiceError.missingRecord }
            draft.category = category
        }
        return draft
    }

    private func wallet(_ id: UUID) throws -> Wallet {
        let descriptor = FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })
        guard let wallet = try context.fetch(descriptor).first else { throw ServiceError.missingRecord }
        return wallet
    }
}
