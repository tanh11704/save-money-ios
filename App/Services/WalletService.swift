import Foundation
import SwiftData

struct WalletDraft {
    var name = ""
    var kind: WalletKind = .cash
    var openingBalance: Int64 = 0
}

@MainActor
struct WalletService {
    struct BalancePreview {
        let before: Int64
        let after: Int64
        let hasTransactions: Bool
    }

    let container: ModelContainer
    var origin: UUID? = nil

    static func validate(_ draft: WalletDraft, wallets: [Wallet], editing id: UUID? = nil) throws {
        let name = try ManagementValidation.name(draft.name)
        guard (-MoneyFormatter.maximumInput...MoneyFormatter.maximumInput).contains(draft.openingBalance) else {
            throw ManagementError.invalidOpeningBalance
        }
        guard draft.kind != .adjustment else { throw ManagementError.invalidKind }
        guard draft.kind != .person || draft.openingBalance == 0 else { throw ManagementError.personOpeningBalance }
        guard !wallets.contains(where: { $0.id != id && $0.isPerson == (draft.kind == .person) && ManagementValidation.matches($0.name, name) }) else {
            throw ManagementError.duplicateName
        }
    }

    static func openingBalance(magnitude: Int64, isDebt: Bool) throws -> Int64 {
        guard (0...MoneyFormatter.maximumInput).contains(magnitude) else { throw ManagementError.invalidOpeningBalance }
        return isDebt ? -magnitude : magnitude
    }

    static func magnitude(of amount: Int64) -> Int64 {
        Int64(exactly: amount.magnitude) ?? Int64.max
    }

    static func displayOpening(magnitude: Int64, isDebt: Bool) -> String {
        // The keypad state is nonnegative, even for a legacy out-of-range balance.
        MoneyFormatter.string(from: isDebt ? -max(0, magnitude) : max(0, magnitude))
    }

    static func preview(wallet: Wallet, openingBalance: Int64, transactions: [Transaction]) throws -> BalancePreview {
        BalancePreview(before: try BalanceCalculator.balance(for: wallet, transactions: transactions),
                       after: try BalanceCalculator.balance(for: wallet, transactions: transactions, openingBalance: openingBalance),
                       hasTransactions: transactions.contains { $0.wallet?.id == wallet.id || $0.toWallet?.id == wallet.id })
    }

    @discardableResult
    func create(_ draft: WalletDraft) throws -> UUID {
        try ManagementPersistence(container: container, origin: origin).write { context in
            try Self.validate(draft, wallets: context.fetch(FetchDescriptor<Wallet>()))
            let wallet = Wallet(name: try ManagementValidation.name(draft.name), openingBalance: draft.openingBalance, kind: draft.kind)
            context.insert(wallet)
            return wallet.id
        }
    }

    func update(id: UUID, with draft: WalletDraft) throws {
        try ManagementPersistence(container: container, origin: origin).write { context in
            let wallets = try context.fetch(FetchDescriptor<Wallet>())
            guard let wallet = wallets.first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
            guard !wallet.isAdjustment, wallet.isPerson == (draft.kind == .person) else { throw ManagementError.invalidKind }
            try Self.validate(draft, wallets: wallets, editing: id)
            _ = try Self.preview(wallet: wallet, openingBalance: draft.openingBalance,
                                 transactions: context.fetch(FetchDescriptor<Transaction>()))
            wallet.name = try ManagementValidation.name(draft.name)
            wallet.kindRaw = draft.kind.rawValue
            wallet.openingBalance = draft.openingBalance
        }
    }

    func archive(id: UUID) throws {
        try ManagementPersistence(container: container, origin: origin).write { context in
            let wallets = try context.fetch(FetchDescriptor<Wallet>())
            guard let wallet = wallets.first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
            guard !wallet.isArchived else { return }
            guard !wallet.isAdjustment else { throw ManagementError.invalidKind }
            if wallet.isPerson {
                guard try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>()), allowMissingCategory: true) == 0 else { throw ManagementError.personOutstanding }
            } else {
                guard wallets.filter({ !$0.isArchived && $0.isOwn }).count > 1 else { throw ManagementError.lastActiveWallet }
            }
            wallet.isArchived = true
        }
    }

    func restore(id: UUID) throws {
        try ManagementPersistence(container: container, origin: origin).write { context in
            let wallets = try context.fetch(FetchDescriptor<Wallet>())
            guard let wallet = wallets.first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
            wallet.isArchived = false
        }
    }
}

/// Records the difference between the app's balance and the real balance of one wallet.
/// The difference is a transfer to or from a hidden adjustment wallet, so it never counts as
/// income or expense (statistics, budgets and alerts already exclude transfers) and the opening
/// balance — and therefore every earlier day's balance — stays untouched.
@MainActor
struct BalanceAdjustmentService {
    enum AdjustmentError: LocalizedError, Equatable {
        case alreadyMatches, notOwnWallet, outOfRange
        var errorDescription: String? {
            switch self {
            case .alreadyMatches: return "Số dư đã khớp, không cần điều chỉnh."
            case .notOwnWallet: return "Chỉ điều chỉnh được ví của bạn đang dùng."
            case .outOfRange: return "Chênh lệch tối đa 999.999.999.999 đồng mỗi lần điều chỉnh."
            }
        }
    }

    /// Same text as `WalletKind.adjustment.title`; nonisolated so any context can read it.
    nonisolated static var walletName: String { WalletKind.adjustment.title }

    let container: ModelContainer
    var origin: UUID? = nil

    /// `actual − current`, overflow-checked and limited to one transaction's maximum amount.
    static func difference(current: Int64, actual: Int64) throws -> Int64 {
        let (delta, overflow) = actual.subtractingReportingOverflow(current)
        guard !overflow, delta != Int64.min, abs(delta) <= MoneyFormatter.maximumInput else { throw AdjustmentError.outOfRange }
        guard delta != 0 else { throw AdjustmentError.alreadyMatches }
        return delta
    }

    /// Creates exactly one transfer, and the adjustment wallet on first use, in a single save.
    @discardableResult
    func adjust(walletID: UUID, to actual: Int64, date: Date = Date(), note: String = "") throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let wallets = try context.fetch(FetchDescriptor<Wallet>())
            guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.isOwn, !wallet.isArchived else {
                throw AdjustmentError.notOwnWallet
            }
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            let current = try BalanceCalculator.balance(for: wallet, transactions: transactions, allowMissingCategory: true)
            let delta = try Self.difference(current: current, actual: actual)
            let system: Wallet
            if let existing = wallets.first(where: \.isAdjustment) {
                system = existing
                system.isArchived = false
            } else {
                system = Wallet(name: Self.walletName, openingBalance: 0, kind: .adjustment)
                context.insert(system)
            }
            let draft = TransactionDraft(amount: abs(delta), kind: .transfer, date: date, note: note,
                                         wallet: delta > 0 ? system : wallet, toWallet: delta > 0 ? wallet : system)
            try TransactionValidator.validate(draft)
            let transaction = Transaction(amount: draft.amount, kind: .transfer, date: date, note: note,
                                          wallet: draft.wallet!, toWallet: draft.toWallet)
            context.insert(transaction)
            try context.save()
            NotificationCenter.default.post(name: .ledgerDidChange, object: container,
                                            userInfo: ["transaction": true, "origin": origin?.uuidString ?? ""])
            return transaction.id
        } catch {
            context.rollback()
            throw error
        }
    }
}
