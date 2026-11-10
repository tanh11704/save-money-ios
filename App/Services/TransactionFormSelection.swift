import Foundation

struct TransactionFormSelection {
    static func wallets(_ wallets: [Wallet], retaining originalID: UUID? = nil, excluding excludedID: UUID? = nil) -> [Wallet] {
        wallets.filter { (!$0.isArchived || $0.id == originalID) && $0.id != excludedID }
    }

    static func categories(_ categories: [Category], kind: TransactionKind, retaining originalID: UUID? = nil,
                           recentID: UUID? = nil) -> [Category] {
        guard kind != .transfer else { return [] }
        return categories.filter { $0.kindRaw == kind.rawValue && (!$0.isArchived || $0.id == originalID) }.sorted {
            if ($0.id == recentID) != ($1.id == recentID) { return $0.id == recentID }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func restoring(_ input: TransactionDraft, wallets: [Wallet], categories: [Category],
                          recent: RecentSelectionStore, preserveWallet: Bool = false) -> TransactionDraft {
        var draft = input.changingKind(to: input.kind)
        let selection = recent.selection(for: draft.kind, wallets: wallets, categories: categories)
        let active = self.wallets(wallets)
        if !preserveWallet {
            draft.wallet = active.first { $0.id == selection.walletID } ?? active.first
        }
        let availableCategories = self.categories(categories, kind: draft.kind, recentID: selection.categoryID)
        draft.category = availableCategories.first { $0.id == selection.categoryID } ?? availableCategories.first
        if draft.kind == .transfer {
            let destinations = self.wallets(wallets, excluding: draft.wallet?.id)
            draft.toWallet = destinations.first { $0.id == selection.destinationID } ?? destinations.first
        }
        return draft
    }

    static func selectingWallet(_ wallet: Wallet, in input: TransactionDraft, available: [Wallet]) -> TransactionDraft {
        var draft = input
        draft.wallet = wallet
        if draft.kind == .transfer, draft.toWallet?.id == wallet.id {
            draft.toWallet = wallets(available, excluding: wallet.id).first
        }
        return draft
    }
}
