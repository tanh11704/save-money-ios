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
            guard wallet.isPerson == (draft.kind == .person) else { throw ManagementError.invalidKind }
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
            if wallet.isPerson {
                guard try BalanceCalculator.balance(for: wallet, transactions: context.fetch(FetchDescriptor<Transaction>()), allowMissingCategory: true) == 0 else { throw ManagementError.personOutstanding }
            } else {
                guard wallets.filter({ !$0.isArchived && !$0.isPerson }).count > 1 else { throw ManagementError.lastActiveWallet }
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
