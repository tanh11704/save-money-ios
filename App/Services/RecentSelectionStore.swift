import Foundation

struct RecentSelectionStore {
    struct Selection: Equatable {
        var walletID: UUID?
        var categoryID: UUID?
        var destinationID: UUID?
    }

    private let defaults: UserDefaults
    private let prefix = "SaveMoney.recentSelection."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func remember(_ draft: TransactionDraft) {
        set(draft.wallet?.id, field: "wallet", kind: draft.kind)
        set(draft.kind == .transfer ? nil : draft.category?.id, field: "category", kind: draft.kind)
        set(draft.kind == .transfer ? draft.toWallet?.id : nil, field: "destination", kind: draft.kind)
    }

    /// Resolve only against currently selectable records, never resurrect archived IDs.
    func selection(for kind: TransactionKind, wallets: [Wallet], categories: [Category]) -> Selection {
        let walletID = get("wallet", kind: kind)
        let categoryID = get("category", kind: kind)
        let destinationID = get("destination", kind: kind)
        let wallet = wallets.first { $0.id == walletID && !$0.isArchived }
        let category = categories.first { $0.id == categoryID && !$0.isArchived && $0.kindRaw == kind.rawValue }
        let destination = wallets.first { $0.id == destinationID && !$0.isArchived && $0.id != wallet?.id }
        return Selection(walletID: wallet?.id,
                         categoryID: kind == .transfer ? nil : category?.id,
                         destinationID: kind == .transfer ? destination?.id : nil)
    }

    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) { defaults.removeObject(forKey: key) }
    }

    private func set(_ id: UUID?, field: String, kind: TransactionKind) {
        let key = prefix + kind.rawValue + "." + field
        if let id { defaults.set(id.uuidString, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private func get(_ field: String, kind: TransactionKind) -> UUID? {
        defaults.string(forKey: prefix + kind.rawValue + "." + field).flatMap(UUID.init(uuidString:))
    }
}
