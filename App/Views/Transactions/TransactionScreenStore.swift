import SwiftData
import SwiftUI

/// A retained read context gives both tabs a fresh snapshot after every write.
/// All arithmetic and validation are delegated to Services.
@MainActor
final class TransactionScreenStore: ObservableObject {
    @Published private(set) var wallets: [Wallet] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var budgetRules: [BudgetRule] = []
    @Published private(set) var balances: [UUID: String] = [:]
    @Published private(set) var totalBalance = MoneyFormatter.string(from: 0)
    @Published private(set) var ready = false
    @Published private(set) var snapshotVersion = UUID()
    @Published private(set) var balanceValues: [UUID: Int64] = [:]
    @Published var errorMessage: String?
    let recent = RecentSelectionStore()
    private let budgetAlerts = BudgetAlertService()
    private var container: ModelContainer?
    private var readContext: ModelContext?
    var statisticsContext: ModelContext? { readContext }

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        do {
            try DefaultDataSeeder.installIfNeeded(container: container)
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
        var values: [UUID: Int64] = [:]
        for wallet in wallets {
            let value = try BalanceCalculator.balance(for: wallet, transactions: transactions, allowMissingCategory: true)
            values[wallet.id] = value
            balances[wallet.id] = MoneyFormatter.string(from: value)
        }
        let total = try BalanceCalculator.totalBalance(wallets: wallets, transactions: transactions, allowMissingCategory: true)
        budgetRules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        readContext = context
        self.wallets = wallets
        self.categories = categories
        self.transactions = transactions
        self.balances = balances
        balanceValues = values
        totalBalance = MoneyFormatter.string(from: total)
        errorMessage = nil
        snapshotVersion = UUID()
    }

    func save(_ draft: TransactionDraft, editing id: UUID?) throws {
        guard let container else { throw TransactionService.ServiceError.missingRecord }
        let month = ReportingMonth(containing: draft.date)
        // Read the persisted graph before mutation, not the editable view's state.
        let before = try? budgetProgress(month: month, container: container)
        let service = TransactionService(container: container, recentSelections: recent)
        if let id { try service.update(id: id, with: draft) }
        else { try service.create(draft) }
        if draft.kind == .expense, let before,
           let after = try? budgetProgress(month: month, container: container) {
            let categories = self.categories
            Task { await budgetAlerts.notify(month: month, before: before, after: after, categories: categories) }
        }
        // A successful write must not be offered again if reading the snapshot fails.
        do { try reload() }
        catch { errorMessage = "Đã lưu, nhưng chưa tải lại được số dư. Hãy tải lại lịch sử." }
    }

    private func budgetProgress(month: ReportingMonth, container: ModelContainer) throws -> [BudgetService.Progress] {
        let context = ModelContext(container); context.autosaveEnabled = false
        return try BudgetService.progress(month: month, rules: context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule),
            transactions: context.fetch(FetchDescriptor<Transaction>()))
    }

    func delete(_ id: UUID) {
        guard let container else { return }
        do {
            try TransactionService(container: container).delete(id: id)
            try reload()
        } catch { errorMessage = TransactionPresentation.errorMessage(error) }
    }
    func saveWallet(_ draft: WalletDraft, editing id: UUID?) throws {
        guard let container else { throw ManagementError.missingRecord }
        let service = WalletService(container: container)
        if let id { try service.update(id: id, with: draft) }
        else { try service.create(draft) }
        refreshAfterManagementWrite()
    }

    func archiveWallet(_ id: UUID) throws {
        guard let container else { throw ManagementError.missingRecord }
        try WalletService(container: container).archive(id: id)
        refreshAfterManagementWrite()
    }

    func restoreWallet(_ id: UUID) throws {
        guard let container else { throw ManagementError.missingRecord }
        try WalletService(container: container).restore(id: id)
        refreshAfterManagementWrite()
    }

    func saveCategory(_ draft: CategoryDraft, editing id: UUID?) throws {
        guard let container else { throw ManagementError.missingRecord }
        let service = CategoryService(container: container)
        if let id { try service.update(id: id, with: draft) }
        else { try service.create(draft) }
        refreshAfterManagementWrite()
    }

    func archiveCategory(_ id: UUID) throws {
        guard let container else { throw ManagementError.missingRecord }
        try CategoryService(container: container).archive(id: id)
        refreshAfterManagementWrite()
    }

    func restoreCategory(_ id: UUID) throws {
        guard let container else { throw ManagementError.missingRecord }
        try CategoryService(container: container).restore(id: id)
        refreshAfterManagementWrite()
    }

    func categoryHasTransactions(_ id: UUID) -> Bool {
        transactions.contains { $0.category?.id == id }
    }

    func budgetSubtitles(on date: Date) -> [UUID: String] {
        do {
            let progress = try BudgetService.progress(month: ReportingMonth(containing: date), rules: budgetRules, transactions: transactions)
            return Dictionary(uniqueKeysWithValues: progress.compactMap { progress in
                guard case .category(let id) = progress.scope else { return nil }
                return (id, BudgetPresentation.remaining(progress))
            })
        } catch { return [:] }
    }

    func saveBudget(_ limit: Int64, scope: BudgetRule.Scope, month: ReportingMonth) throws {
        guard let container else { throw ManagementError.missingRecord }
        try ManagementPersistence(container: container).write { context in
            try BudgetPersistence.setLimit(limit, scope: scope, from: month, context: context)
        }
        refreshAfterManagementWrite()
        Task { _ = try? await SystemReminderClient().requestPermission() }
    }

    func turnOffBudget(scope: BudgetRule.Scope, month: ReportingMonth) throws {
        guard let container else { throw ManagementError.missingRecord }
        try ManagementPersistence(container: container).write { context in
            try BudgetPersistence.turnOff(scope: scope, from: month, context: context)
        }
        refreshAfterManagementWrite()
    }

    private func refreshAfterManagementWrite() {
        do { try reload() }
        catch { errorMessage = "Đã lưu thay đổi, nhưng chưa tải lại được dữ liệu. Hãy tải lại." }
    }

}
