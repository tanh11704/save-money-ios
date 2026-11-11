import SwiftData
import SwiftUI

/// A retained read context gives both tabs a fresh snapshot after every write.
/// All arithmetic and validation are delegated to Services.
@MainActor
final class TransactionScreenStore: ObservableObject {
    struct AddPrefill: Identifiable { let id = UUID(); let kind: TransactionKind?; let amount: Int64? }
    struct UndoAction: Identifiable {
        let id = UUID()
        let snapshot: TransactionSnapshot
        let restore: Bool
        let message: String
        let expiresAt = Date().addingTimeInterval(5)
    }
    @Published private(set) var undoAction: UndoAction?
    @Published var addPrefill: AddPrefill?
    @Published private(set) var netWorth: NetWorth?
    @Published private(set) var debtLabels: [UUID: DebtPresentation.Label] = [:]
    @Published private(set) var wallets: [Wallet] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var recurringRules: [RecurringRule] = []
    @Published private(set) var budgetRules: [BudgetRule] = []
    @Published private(set) var balances: [UUID: String] = [:]
    @Published private(set) var totalBalance = MoneyFormatter.string(from: 0)
    @Published private(set) var ready = false
    @Published private(set) var snapshotVersion = UUID()
    @Published private(set) var balanceValues: [UUID: Int64] = [:]
    @Published var errorMessage: String?
    @Published private(set) var currentMonthReport: StatsService.Report?
    @Published private(set) var lastActivityByWallet: [UUID: Date] = [:]
    @Published private(set) var availableMonths: [ReportingMonth] = []
    private var budgetCache: [ReportingMonth: Result<[BudgetService.Progress], Error>] = [:]
    private(set) var isWriting = false
    private let origin = UUID()
    #if DEBUG
    private(set) var reloadCount = 0
    #endif
    let recent = RecentSelectionStore()
    private let budgetAlerts: BudgetAlertService

    init(budgetAlerts: BudgetAlertService? = nil) {
        self.budgetAlerts = budgetAlerts ?? BudgetAlertService()
    }
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

    func receiveLedgerChange(_ notification: Notification) {
        guard (notification.userInfo?["origin"] as? String) != origin.uuidString, ready, !isWriting else { return }
        do { try reload() }
        catch { errorMessage = "Chưa tải lại được dữ liệu. Tải lại." }
    }

    func reload() throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\Wallet.createdAt), SortDescriptor(\Wallet.name)]))
        let categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.name)]))
        let transactions = try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]))
        let values = try BalanceCalculator.balances(wallets: wallets, transactions: transactions, allowMissingCategory: true)
        let balances = values.mapValues { MoneyFormatter.string(from: $0) }
        let worth = try NetWorth.make(wallets: wallets, balances: values)
        let labels = try DebtPresentation.labels(transactions: transactions)
        recurringRules = try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [SortDescriptor(\RecurringRule.createdAt)]))
        budgetRules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        readContext = context
        self.wallets = wallets
        self.categories = categories
        self.transactions = transactions
        self.balances = balances
        balanceValues = values
        netWorth = worth
        debtLabels = labels
        totalBalance = MoneyFormatter.string(from: worth.ownWallets)
        errorMessage = nil
        budgetCache.removeAll()
        _ = progress(in: ReportingMonth())
        currentMonthReport = try? StatsService.report(month: ReportingMonth(), transactions: transactions)
        availableMonths = Array(Set(transactions.map { ReportingMonth(containing: $0.date) })).sorted { $0 > $1 }
        var activity: [UUID: Date] = [:]
        for transaction in transactions {
            for id in [transaction.wallet?.id, transaction.toWallet?.id].compactMap({ $0 }) {
                activity[id] = max(activity[id] ?? .distantPast, transaction.date)
            }
        }
        lastActivityByWallet = activity
        #if DEBUG
        reloadCount += 1
        #endif
        snapshotVersion = UUID()
    }

    @discardableResult
    func save(_ draft: TransactionDraft, editing id: UUID?) throws -> UUID {
        guard let container else { throw TransactionService.ServiceError.missingRecord }
        let month = ReportingMonth(containing: draft.date)
        isWriting = true
        defer { isWriting = false }
        let before = progress(in: month)
        let service = TransactionService(container: container, recentSelections: recent, origin: origin)
        let savedID: UUID
        if let id { try service.update(id: id, with: draft); savedID = id }
        else { savedID = try service.create(draft) }
        if id != nil, undoAction?.snapshot.id == savedID { undoAction = nil }
        // Refresh once; do not offer a committed write again if refresh fails.
        do {
            try reload()
            if draft.kind == .expense {
                let after = progress(in: month), categories = self.categories
                Task { await budgetAlerts.notify(month: month, before: before, after: after, categories: categories) }
            }
            if id == nil, let transaction = transactions.first(where: { $0.id == savedID }) {
                undoAction = UndoAction(snapshot: TransactionSnapshot(transaction), restore: false, message: "Đã lưu " + TransactionPresentation.amount(transaction) + " · " + TransactionPresentation.title(transaction))
            }
        } catch { errorMessage = "Đã lưu, nhưng chưa tải lại được số dư. Tải lại lịch sử." }
        return savedID
    }

    private func budgetResult(in month: ReportingMonth) -> Result<[BudgetService.Progress], Error> {
        if let cached = budgetCache[month] { return cached }
        let result = Result { try BudgetService.progress(month: month, rules: budgetRules, transactions: transactions) }
        budgetCache[month] = result
        return result
    }

    func progress(in month: ReportingMonth) -> [BudgetService.Progress] {
        (try? budgetResult(in: month).get()) ?? []
    }

    func budgetError(in month: ReportingMonth) -> String? {
        if case .failure(let error) = budgetResult(in: month) { return TransactionPresentation.errorMessage(error) }
        return nil
    }

    func delete(_ id: UUID) {
        isWriting = true
        defer { isWriting = false }
        guard let container else { return }
        do {
            guard let transaction = transactions.first(where: { $0.id == id }) else { throw TransactionService.ServiceError.missingRecord }
            let snapshot = TransactionSnapshot(transaction)
            let message = "Đã xóa " + TransactionPresentation.amount(transaction) + " · " + TransactionPresentation.title(transaction)
            try TransactionService(container: container, origin: origin).delete(id: id)
            undoAction = UndoAction(snapshot: snapshot, restore: true, message: message)
            refreshAfterManagementWrite()
        } catch { errorMessage = TransactionPresentation.errorMessage(error) }
    }
    /// Records the real balance of an own wallet; the difference is undoable like any new transaction.
    func adjustBalance(walletID: UUID, to actual: Int64, date: Date, note: String) throws {
        guard let container else { throw ManagementError.missingRecord }
        isWriting = true
        defer { isWriting = false }
        let id = try BalanceAdjustmentService(container: container, origin: origin).adjust(walletID: walletID, to: actual, date: date, note: note)
        do {
            try reload()
            if let transaction = transactions.first(where: { $0.id == id }) {
                undoAction = UndoAction(snapshot: TransactionSnapshot(transaction), restore: false,
                                        message: "Đã điều chỉnh · \(TransactionPresentation.title(transaction))")
            }
        } catch { errorMessage = "Đã điều chỉnh, nhưng chưa tải lại được số dư. Tải lại lịch sử." }
    }

    func clearUndo() { undoAction = nil }

    func expireUndo(_ id: UUID) {
        if undoAction?.id == id { undoAction = nil }
    }

    func undo() {
        guard let action = undoAction, action.expiresAt > Date(), let container else { undoAction = nil; return }
        isWriting = true
        defer { isWriting = false }
        do {
            let service = TransactionService(container: container, origin: origin)
            if action.restore { try service.restore(action.snapshot) }
            else { try service.delete(ifUnchanged: action.snapshot) }
            undoAction = nil
            refreshAfterManagementWrite()
        } catch { errorMessage = "Không thể hoàn tác: " + TransactionPresentation.errorMessage(error) }
    }

    func saveWallet(_ draft: WalletDraft, editing id: UUID?) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        let service = WalletService(container: container, origin: origin)
        if let id { try service.update(id: id, with: draft) }
        else { _ = try service.create(draft) }
        refreshAfterManagementWrite()
    }

    func archiveWallet(_ id: UUID) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try WalletService(container: container, origin: origin).archive(id: id)
        refreshAfterManagementWrite()
    }

    func restoreWallet(_ id: UUID) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try WalletService(container: container, origin: origin).restore(id: id)
        refreshAfterManagementWrite()
    }

    func saveCategory(_ draft: CategoryDraft, editing id: UUID?) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        let service = CategoryService(container: container, origin: origin)
        if let id { try service.update(id: id, with: draft) }
        else { _ = try service.create(draft) }
        refreshAfterManagementWrite()
    }

    func archiveCategory(_ id: UUID) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try CategoryService(container: container, origin: origin).archive(id: id)
        refreshAfterManagementWrite()
    }

    func restoreCategory(_ id: UUID) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try CategoryService(container: container, origin: origin).restore(id: id)
        refreshAfterManagementWrite()
    }

    func categoryKindIsLocked(_ id: UUID) -> Bool {
        transactions.contains { $0.category?.id == id } || budgetRules.contains { $0.scope == .category(id) } || recurringRules.contains { $0.category?.id == id }
    }

    func overBudgetCategories(on date: Date) -> Set<UUID> {
        let progress = progress(in: ReportingMonth(containing: date))
        return Set(progress.compactMap { value in
            guard value.level == .over, case .category(let id) = value.scope else { return nil }
            return id
        })
    }

    func budgetSubtitles(on date: Date, compact: Bool = false) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: progress(in: ReportingMonth(containing: date)).compactMap { value in
            guard case .category(let id) = value.scope else { return nil }
            return (id, compact ? BudgetPresentation.remainingCompact(value) : BudgetPresentation.remaining(value))
        })
    }

    func saveRecurring(_ draft: RecurringDraft, editing id: UUID?) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try RecurringPersistence(container: container, origin: origin).save(draft, editing: id)
        refreshAfterManagementWrite()
    }

    func setRecurringPaused(_ paused: Bool, id: UUID) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try RecurringPersistence(container: container, origin: origin).setPaused(paused, id: id)
        refreshAfterManagementWrite()
    }

    func saveBudget(_ limit: Int64, scope: BudgetRule.Scope, month: ReportingMonth) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try ManagementPersistence(container: container, origin: origin).write { context in
            try BudgetPersistence.setLimit(limit, scope: scope, from: month, context: context)
        }
        refreshAfterManagementWrite()
        Task { _ = try? await SystemReminderClient().requestPermission() }
    }

    func turnOffBudget(scope: BudgetRule.Scope, month: ReportingMonth) throws {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        try ManagementPersistence(container: container, origin: origin).write { context in
            try BudgetPersistence.turnOff(scope: scope, from: month, context: context)
        }
        refreshAfterManagementWrite()
    }

    private func refreshAfterManagementWrite() {
        do { try reload() }
        catch { errorMessage = "Đã lưu thay đổi, nhưng chưa tải lại được dữ liệu. Hãy tải lại." }
    }

}
