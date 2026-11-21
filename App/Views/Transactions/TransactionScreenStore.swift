import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

/// A retained read context gives both tabs a fresh snapshot after every write.
/// All arithmetic and validation are delegated to Services.
@MainActor
final class TransactionScreenStore: ObservableObject {
    struct AddPrefill: Identifiable {
        let id = UUID(); let kind: TransactionKind?; let amount: Int64?
        /// Shortcuts and URLs make the user pick the category; in-app buttons keep the remembered one.
        var clearsSelection = true
    }
    struct UndoAction: Identifiable {
        let id = UUID()
        let snapshot: TransactionSnapshot
        /// Rows created together with `snapshot` (a transfer's fee), undone with it.
        var related: [TransactionSnapshot] = []
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
    /// The cycle that just ended, shown once as an end-of-cycle summary.
    @Published var pendingCycleSummary: ReportingMonth?
    private var lastWidgetSnapshot: WidgetSnapshot?
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
        publishWidgetSnapshot()
        scheduleCardReminders()
        scheduleDailyReminder()
    }

    var loggingStreak: Int { LoggingStreak.days(transactions: transactions) }

    /// Recurring payments, installments and card due dates in the next `days` days, soonest first.
    func upcoming(days: Int = 7, now: Date = Date()) -> [UpcomingItem] {
        let calendar = LocalCalendar.calendar
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        var items: [UpcomingItem] = []
        for rule in recurringRules where !rule.isPaused {
            guard let next = RecurringPresentation.nextDate(rule), next >= today, next <= horizon else { continue }
            items.append(UpcomingItem(id: "rule.\(rule.id.uuidString)", kind: rule.endDate == nil ? .recurring : .installment,
                                      title: rule.title, date: next, amount: rule.amount))
        }
        for card in creditCards {
            guard let status = cardStatus(card, now: now), status.debt > 0, status.dueDate <= horizon else { continue }
            items.append(UpcomingItem(id: "card.\(card.id.uuidString)", kind: .cardDue, title: "Hạn thẻ \(card.name)", date: status.dueDate, amount: status.debt))
        }
        return items.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }

    /// 21:00 "Hôm nay bạn đã chi gì chưa?" — today if nothing is logged yet, otherwise tomorrow.
    /// Rescheduled on every reload, so logging something cancels today's reminder.
    func scheduleDailyReminder(now: Date = Date()) {
        let id = "SaveMoney.dailyLogReminder"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard UserDefaults.standard.bool(forKey: AppearanceSettings.dailyReminderKey) else { return }
        let calendar = LocalCalendar.calendar
        guard var fire = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now) else { return }
        if LoggingStreak.hasLoggedToday(transactions: transactions, now: now) || fire <= now {
            fire = calendar.date(byAdding: .day, value: 1, to: fire)!
        }
        let content = UNMutableNotificationContent()
        content.title = "Hôm nay bạn đã chi gì chưa?"
        let streak = loggingStreak
        content.body = streak > 1 ? "Ghi lại để giữ chuỗi \(streak) ngày ghi chép." : "Mất vài giây để ghi lại chi tiêu hôm nay."
        content.sound = .default
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }


    // MARK: Widget, cycle summary, cards and installments

    /// Writes the widget summary to the App Group (no-op without one) and refreshes widgets on change.
    func publishWidgetSnapshot(now: Date = Date()) {
        let showsAmounts = UserDefaults.standard.bool(forKey: SharedContainer.showsAmountsKey)
        let snapshot = WidgetSnapshot.make(transactions: transactions, totalBalance: netWorth?.ownWallets ?? 0,
                                           rules: budgetRules, fixed: fixedCosts(in: ReportingMonth(containing: now)),
                                           showsAmounts: showsAmounts, now: now)
        var comparable = snapshot; comparable.generatedAt = lastWidgetSnapshot?.generatedAt ?? snapshot.generatedAt
        guard comparable != lastWidgetSnapshot else { return }
        if SharedContainer.write(snapshot) {
            lastWidgetSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Offers the summary of the cycle that just ended, once.
    func checkCycleSummary(now: Date = Date()) {
        guard pendingCycleSummary == nil else { return }
        pendingCycleSummary = CycleSummaryTracker.pending(now: now, transactions: transactions)
    }

    func dismissCycleSummary() {
        if let month = pendingCycleSummary { CycleSummaryTracker.markShown(month) }
        pendingCycleSummary = nil
    }

    /// Fixed categories and recurring expenses still to come in `month`; kept out of the daily spread.
    func fixedCosts(in month: ReportingMonth) -> FixedCosts {
        FixedCosts.make(categories: categories, rules: recurringRules, month: month)
    }

    /// Fixed spending booked in `month` plus recurring expenses still to come; zero when it cannot be computed.
    func fixedTotals(in month: ReportingMonth) -> FixedCosts.Totals {
        (try? fixedCosts(in: month).totals(month: month, transactions: transactions)) ?? .zero
    }

    func flexibleAllowance(now: Date = Date()) -> StatsService.FlexibleAllowance? {
        let month = ReportingMonth(containing: now)
        guard let rule = BudgetService.activeRule(for: .total, in: month, rules: budgetRules) else { return nil }
        return try? StatsService.flexibleAllowance(limit: rule.limit, month: month, transactions: transactions,
                                                   fixed: fixedCosts(in: month), now: now)
    }

    var installments: [InstallmentProgress] {
        recurringRules.compactMap(InstallmentProgress.make).sorted {
            if $0.isFinished != $1.isFinished { return !$0.isFinished }
            return ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture)
        }
    }

    var creditCards: [Wallet] { wallets.filter { !$0.isArchived && WalletKind(rawValue: $0.kindRaw) == .card } }

    func cardStatus(_ wallet: Wallet, now: Date = Date()) -> CreditCardStatus? {
        guard let settings = CreditCardSettingsStore.load(wallet.id) else { return nil }
        return CreditCardStatus.make(wallet: wallet, balance: balanceValues[wallet.id] ?? 0, settings: settings, transactions: transactions, now: now)
    }

    func saveCardSettings(_ settings: CreditCardSettings?, for walletID: UUID) {
        CreditCardSettingsStore.save(settings, for: walletID)
        if settings?.remindsBeforeDue == true { Task { _ = try? await SystemReminderClient().requestPermission() } }
        scheduleCardReminders()
        snapshotVersion = UUID()
    }

    /// 9:00 three days before and on the due date, only while the card has debt.
    /// Never asks for permission here; that happens when reminders are turned on.
    private func scheduleCardReminders(now: Date = Date()) {
        let cards = wallets.filter { WalletKind(rawValue: $0.kindRaw) == .card }
        var requests: [UNNotificationRequest] = []
        for card in cards where !card.isArchived {
            guard let settings = CreditCardSettingsStore.load(card.id), settings.remindsBeforeDue,
                  let status = cardStatus(card, now: now), status.debt > 0 else { continue }
            for daysBefore in [3, 0] {
                guard let day = LocalCalendar.calendar.date(byAdding: .day, value: -daysBefore, to: status.dueDate),
                      let fire = LocalCalendar.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = daysBefore == 0 ? "Hôm nay đến hạn thẻ \(card.name)" : "Còn \(daysBefore) ngày đến hạn thẻ \(card.name)"
                let showsAmounts = UserDefaults.standard.bool(forKey: BudgetAlertService.showsAmountsKey)
                content.body = showsAmounts ? "Dư nợ hiện tại \(MoneyFormatter.string(from: status.debt)). Hạn \(TransactionPresentation.shortDate(status.dueDate))."
                                            : "Thanh toán trước \(TransactionPresentation.shortDate(status.dueDate)) để tránh phí trễ hạn."
                content.sound = .default
                var components = LocalCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                components.calendar = LocalCalendar.calendar; components.timeZone = LocalCalendar.calendar.timeZone
                requests.append(UNNotificationRequest(identifier: "SaveMoney.cardDue.\(card.id.uuidString).\(daysBefore)", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
        }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("SaveMoney.cardDue.") }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            requests.forEach { center.add($0) }
        }
    }

    /// Saves an installment plan as a monthly recurring expense with an end date.
    /// Without a chosen category, an expense category "Trả góp" is reused or created.
    func saveInstallment(name: String, perPeriod: Int64, periods: Int, firstPayment: Date,
                         wallet: Wallet?, category: Category?, editing id: UUID? = nil) throws {
        guard let end = InstallmentProgress.endDate(start: firstPayment, periods: periods) else { throw InstallmentError.periods }
        var chosen = category
        if chosen == nil {
            let name = "Trả góp"
            if let existing = categories.first(where: { $0.kindRaw == TransactionKind.expense.rawValue && !$0.isArchived
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) == .orderedSame }) {
                chosen = existing
            } else {
                try saveCategory(CategoryDraft(name: name, kind: .expense, icon: "calendar.badge.clock"), editing: nil)
                chosen = categories.first { $0.kindRaw == TransactionKind.expense.rawValue && !$0.isArchived && $0.name == name }
            }
        }
        let draft = RecurringDraft(name: name, transaction: TransactionDraft(amount: perPeriod, kind: .expense, note: name, wallet: wallet, category: chosen),
                                   frequency: .monthly, interval: 1, startDate: firstPayment, endDate: end)
        try saveRecurring(draft, editing: id)
    }

    enum InstallmentError: LocalizedError {
        case periods
        var errorDescription: String? { "Số kỳ phải từ 1 đến \(InstallmentProgress.maximumPeriods)." }
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
                var message = "Đã lưu " + TransactionPresentation.amount(transaction) + " · " + TransactionPresentation.title(transaction)
                // Immediate feedback on what the expense means for today.
                if draft.kind == .expense, LocalCalendar.calendar.isDateInToday(draft.date), let allowance = flexibleAllowance() {
                    if fixedCosts(in: ReportingMonth(containing: transaction.date)).isFixed(transaction) {
                        message += " · khoản cố định, không trừ vào hôm nay"
                    } else {
                        message += allowance.leftToday >= 0 ? " · hôm nay còn \(MoneyFormatter.compact(allowance.leftToday))"
                                                            : " · hôm nay vượt \(MoneyFormatter.compact(-allowance.leftToday))"
                    }
                }
                undoAction = UndoAction(snapshot: TransactionSnapshot(transaction), restore: false, message: message)
            }
        } catch { errorMessage = "Đã lưu, nhưng chưa tải lại được số dư. Tải lại lịch sử." }
        return savedID
    }

    /// New transfer between own wallets plus an optional fee expense from the source wallet.
    @discardableResult
    func saveTransfer(_ draft: TransactionDraft, fee: Int64) throws -> UUID {
        guard fee > 0 else { return try save(draft, editing: nil) }
        guard let container else { throw TransactionService.ServiceError.missingRecord }
        let month = ReportingMonth(containing: draft.date)
        isWriting = true
        defer { isWriting = false }
        let before = progress(in: month)
        let ids = try TransactionService(container: container, recentSelections: recent, origin: origin).createTransfer(draft, fee: fee)
        do {
            try reload()
            // The fee is an expense, so it can cross a budget threshold.
            let after = progress(in: month), categories = self.categories
            Task { await budgetAlerts.notify(month: month, before: before, after: after, categories: categories) }
            if let transfer = transactions.first(where: { $0.id == ids.transfer }) {
                let related = transactions.filter { $0.id == ids.fee }.map(TransactionSnapshot.init)
                undoAction = UndoAction(snapshot: TransactionSnapshot(transfer), related: related, restore: false,
                                        message: "Đã lưu " + TransactionPresentation.amount(transfer) + " · phí " + MoneyFormatter.string(from: fee))
            }
        } catch { errorMessage = "Đã lưu, nhưng chưa tải lại được số dư. Tải lại lịch sử." }
        return ids.transfer
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
            else { try service.delete(ifUnchanged: [action.snapshot] + action.related) }
            undoAction = nil
            refreshAfterManagementWrite()
        } catch { errorMessage = "Không thể hoàn tác: " + TransactionPresentation.errorMessage(error) }
    }

    @discardableResult
    func saveWallet(_ draft: WalletDraft, editing id: UUID?) throws -> UUID {
        isWriting = true
        defer { isWriting = false }
        guard let container else { throw ManagementError.missingRecord }
        let service = WalletService(container: container, origin: origin)
        let savedID: UUID
        if let id { try service.update(id: id, with: draft); savedID = id }
        else { savedID = try service.create(draft) }
        refreshAfterManagementWrite()
        return savedID
    }

    /// Display preferences kept outside SwiftData; republishes so cards and forms refresh.
    func setWalletColor(_ index: Int?, for id: UUID) {
        WalletAppearance.setColorIndex(index, for: id)
        snapshotVersion = UUID()
    }

    var mainWalletID: UUID? {
        guard let id = MainWallet.id, wallets.contains(where: { $0.id == id && $0.isOwn && !$0.isArchived }) else { return nil }
        return id
    }

    func setMainWallet(_ id: UUID?) {
        MainWallet.id = id
        snapshotVersion = UUID()
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
