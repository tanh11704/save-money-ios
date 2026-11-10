import SwiftData
import SwiftUI

/// A retained read context gives both tabs a fresh snapshot after every write.
/// All arithmetic and validation are delegated to Services.
@MainActor
final class TransactionScreenStore: ObservableObject {
    @Published private(set) var wallets: [Wallet] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var balances: [UUID: String] = [:]
    @Published private(set) var totalBalance = MoneyFormatter.string(from: 0)
    @Published private(set) var ready = false
    @Published var errorMessage: String?
    @Published var changeToken = UUID()
    let recent = RecentSelectionStore()
    private var container: ModelContainer?
    private var readContext: ModelContext?

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        do {
            try TemporarySampleData.installIfNeeded(container: container)
            try reload()
            ready = true
        } catch { errorMessage = TransactionPresentation.errorMessage(error) }
    }

    func retry() {
        guard let container else { return }
        self.container = nil
        configure(container: container)
    }

    func reload() throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\Wallet.createdAt), SortDescriptor(\Wallet.name)]))
        let categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.name)]))
        let transactions = try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]))
        var balances: [UUID: String] = [:]
        for wallet in wallets {
            balances[wallet.id] = MoneyFormatter.string(from: try BalanceCalculator.balance(for: wallet, transactions: transactions))
        }
        let total = try BalanceCalculator.totalBalance(wallets: wallets, transactions: transactions)
        readContext = context
        self.wallets = wallets
        self.categories = categories
        self.transactions = transactions
        self.balances = balances
        totalBalance = MoneyFormatter.string(from: total)
        changeToken = UUID()
        errorMessage = nil
    }

    func save(_ draft: TransactionDraft, editing id: UUID?) throws {
        guard let container else { return }
        let service = TransactionService(container: container, recentSelections: recent)
        if let id { try service.update(id: id, with: draft) }
        else { try service.create(draft) }
        // A successful write must not be offered again if reading the snapshot fails.
        do { try reload() }
        catch { errorMessage = "Đã lưu, nhưng chưa tải lại được số dư. Hãy tải lại lịch sử." }
    }

    func delete(_ id: UUID) {
        guard let container else { return }
        do {
            try TransactionService(container: container).delete(id: id)
            try reload()
        } catch { errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
