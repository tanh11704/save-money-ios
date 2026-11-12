import Foundation
import SwiftData

/// Owns a non-autosaving context: a failed save rolls back only this operation.
/// IDs are resolved again here so stale UI objects cannot bypass archive validation.
@MainActor
final class TransactionService {
    enum ServiceError: LocalizedError {
        case missingRecord
        var errorDescription: String? { "Dữ liệu không còn tồn tại. Tải lại và thử lại." }
    }

    private let container: ModelContainer
    private var context: ModelContext
    private let recentSelections: RecentSelectionStore?
    private let origin: UUID?

    init(container: ModelContainer, recentSelections: RecentSelectionStore? = nil, origin: UUID? = nil) {
        self.origin = origin
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

    enum FeeError: LocalizedError {
        case invalidFee
        var errorDescription: String? { "Phí chuyển phải từ 0 đến 999.999.999.999 đồng." }
    }

    /// Name of the expense category that transfer fees are recorded under.
    static let transferFeeCategoryName = "Phí chuyển tiền"

    /// Saves a transfer and, when `fee` > 0, an expense of `fee` from the same source wallet
    /// (category "Phí chuyển tiền", created if needed) in one save: both rows or neither.
    /// The fee stays a normal expense, so balances, stats, budgets and backups need no new field.
    @discardableResult
    func createTransfer(_ input: TransactionDraft, fee: Int64) throws -> (transfer: UUID, fee: UUID?) {
        guard (0...MoneyFormatter.maximumInput).contains(fee) else { throw FeeError.invalidFee }
        return try perform {
            let draft = try resolve(input)
            guard draft.kind == .transfer else { throw TransactionValidator.ValidationError.missingDestination }
            try TransactionValidator.validate(draft)
            guard let wallet = draft.wallet, let destination = draft.toWallet else { throw TransactionValidator.ValidationError.missingWallet }
            let transfer = Transaction(amount: draft.amount, kind: .transfer, date: draft.date,
                                       note: draft.note, wallet: wallet, toWallet: destination)
            context.insert(transfer)
            var feeID: UUID?
            if fee > 0 {
                let category = try transferFeeCategory()
                let feeDraft = TransactionDraft(amount: fee, kind: .expense, date: draft.date,
                                                note: "Phí chuyển \(wallet.name) → \(destination.name)", wallet: wallet, category: category)
                try TransactionValidator.validate(feeDraft)
                let expense = Transaction(amount: fee, kind: .expense, date: draft.date, note: feeDraft.note, wallet: wallet, category: category)
                context.insert(expense)
                feeID = expense.id
            }
            try context.save()
            recentSelections?.remember(draft)
            return (transfer.id, feeID)
        }
    }

    /// Reuses an expense category named "Phí chuyển tiền" (restoring it if archived), else creates one.
    private func transferFeeCategory() throws -> Category {
        let name = Self.transferFeeCategoryName
        let matches = try context.fetch(FetchDescriptor<Category>()).filter {
            $0.kindRaw == TransactionKind.expense.rawValue
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) == .orderedSame
        }
        if let active = matches.first(where: { !$0.isArchived }) { return active }
        if let archived = matches.first { archived.isArchived = false; return archived }
        let category = Category(name: name, kind: .expense, icon: "building.columns")
        context.insert(category)
        return category
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

    func restore(_ snapshot: TransactionSnapshot) throws {
        try perform {
            let id = snapshot.id
            guard try context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })) == 0,
                  let kind = TransactionKind(rawValue: snapshot.kind), let walletID = snapshot.walletID else {
                throw ServiceError.missingRecord
            }
            if let key = snapshot.recurrenceKey {
                guard try context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.recurrenceKey == key })) == 0 else {
                    throw ServiceError.missingRecord
                }
            }
            let source = try wallet(walletID)
            var category: Category?
            if let id = snapshot.categoryID {
                category = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first
                guard category != nil else { throw ServiceError.missingRecord }
            }
            let destination = try snapshot.destinationID.map { try wallet($0) }
            let transaction = Transaction(amount: snapshot.amount, kind: kind, date: snapshot.date,
                                          note: snapshot.note, wallet: source, toWallet: destination, category: category)
            transaction.id = snapshot.id
            transaction.recurrenceKey = snapshot.recurrenceKey
            let draft = TransactionDraft(amount: snapshot.amount, kind: kind, date: snapshot.date,
                                         note: snapshot.note, wallet: source, toWallet: destination, category: category)
            // Existing archived references may be restored, but broken relationships may not.
            try TransactionValidator.validate(draft, editing: transaction)
            context.insert(transaction)
            try context.save()
        }
    }

    func delete(ifUnchanged snapshot: TransactionSnapshot) throws {
        try delete(ifUnchanged: [snapshot])
    }

    /// Undo for a write that created several rows (a transfer and its fee): all or nothing.
    func delete(ifUnchanged snapshots: [TransactionSnapshot]) throws {
        try perform {
            for snapshot in snapshots {
                let transaction = try find(snapshot.id)
                guard TransactionSnapshot(transaction) == snapshot else { throw ServiceError.missingRecord }
                context.delete(transaction)
            }
            try context.save()
        }
    }

    private func perform<T>(_ operation: () throws -> T) throws -> T {
        // Fresh identity map on each call: archive changes made elsewhere are visible.
        context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try operation()
            NotificationCenter.default.post(name: .ledgerDidChange, object: container, userInfo: ["transaction": true, "origin": origin?.uuidString ?? ""])
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

/// Immutable undo payload. Relationships are resolved afresh at restore time.
struct TransactionSnapshot: Equatable {
    let id: UUID
    let amount: Int64
    let kind: String
    let date: Date
    let note: String
    let walletID: UUID?
    let destinationID: UUID?
    let categoryID: UUID?
    let recurrenceKey: String?

    init(_ transaction: Transaction) {
        id = transaction.id; amount = transaction.amount; kind = transaction.kindRaw
        date = transaction.date; note = transaction.note; walletID = transaction.wallet?.id
        destinationID = transaction.toWallet?.id; categoryID = transaction.category?.id
        recurrenceKey = transaction.recurrenceKey
    }
}
