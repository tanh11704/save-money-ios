import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AppRuntime: ObservableObject {
    let router = AppRouter.shared
    let container: ModelContainer
    let scheduler: BackupScheduler
    let lock: AppLockService
    let settings: BackupScreenStore
    @Published private(set) var recurringIssues: [RecurringService.Skip] = []
    @Published private(set) var recurringMessage: String?
    private let budgetAlerts: BudgetAlertService
    private var generatedThisActivation = false
    private var generating = false
    private var observers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(container: ModelContainer, scheduler suppliedScheduler: BackupScheduler? = nil, lock suppliedLock: AppLockService? = nil, budgetAlerts suppliedAlerts: BudgetAlertService? = nil) {
        self.container = container
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exporter = BackupExporter(container: container, directory: documents.appendingPathComponent("Backups", isDirectory: true))
        scheduler = suppliedScheduler ?? BackupScheduler(exporter: exporter)
        lock = suppliedLock ?? AppLockService(authenticator: DeviceAuthenticator())
        budgetAlerts = suppliedAlerts ?? BudgetAlertService()
        settings = BackupScreenStore(scheduler: scheduler)
        let failureNotifier = BackupFailureNotifier(client: SystemReminderClient(), defaults: scheduler.defaults)
        scheduler.onAutomaticFailure = { count in Task { await failureNotifier.notify(consecutiveFailures: count, now: Date()) } }
        scheduler.onChange = { [weak settings] in settings?.refresh() }
        observers.append(NotificationCenter.default.addObserver(forName: .ledgerDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let source = notification.object as? ModelContainer, source === container else { return }
            let isTransaction = notification.userInfo?["transaction"] as? Bool == true
            MainActor.assumeIsolated {
                if isTransaction { self?.scheduler.transactionChanged() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .recurringRulesDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let source = notification.object as? ModelContainer, source === container else { return }
            MainActor.assumeIsolated { self?.generateRecurring(force: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .ledgerDidRestore, object: nil, queue: .main) { [weak self] notification in
            guard let source = notification.object as? ModelContainer, source === container else { return }
            MainActor.assumeIsolated {
                self?.scheduler.restored(); self?.settings.refresh()
                self?.recurringMessage = nil; self?.recurringIssues = []
                self?.generatedThisActivation = true // Resume generation on the next opening, not mid-restore.
            }
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func becameActive() {
        lock.becameActive()
        generateRecurring()
        settings.refresh()
    }

    func generateRecurring(force: Bool = false) {
        guard UIApplication.shared.applicationState == .active, lock.state == .unlocked, !settings.isRestoring, !generating,
              force || !generatedThisActivation else { return }
        settings.checkIntegrityIfDue()
        generating = true; generatedThisActivation = true
        defer { generating = false }
        do {
            let context = ModelContext(container), month = ReportingMonth()
            let rules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
            let before = try? BudgetService.progress(month: month, rules: rules, transactions: context.fetch(FetchDescriptor<Transaction>()))
            let result = try RecurringService.generateDue(now: Date(), container: container)
            recurringIssues = result.skipped
            recurringMessage = result.skipped.isEmpty ? nil : "\(result.skipped.count) giao dịch định kỳ không sinh được. Xem lại."
            if result.hasMore { recurringMessage = [recurringMessage, "Còn giao dịch đến hạn; sẽ tiếp tục vào lần mở app sau."].compactMap { $0 }.joined(separator: " ") }
            if result.created > 0 {
                for _ in 0..<result.created { scheduler.transactionChanged() }
                NotificationCenter.default.post(name: .ledgerDidChange, object: container)
                let fresh = ModelContext(container)
                if let before, let after = try? BudgetService.progress(month: month, rules: rules, transactions: fresh.fetch(FetchDescriptor<Transaction>())) {
                    let categories = try fresh.fetch(FetchDescriptor<Category>())
                    Task { await budgetAlerts.notify(month: month, before: before, after: after, categories: categories) }
                }
            }
        } catch { recurringMessage = "Không tạo được giao dịch định kỳ. Dữ liệu được giữ nguyên; hãy thử lại lần mở app sau." }
    }

    func enteredBackground() {
        generatedThisActivation = false
        lock.enteredBackground()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SaveMoney backup") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = scheduler.automatic() // Independent of lock state and of ContentView.
            settings.refresh()
            endBackgroundTask()
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

@MainActor
final class BackupScreenStore: ObservableObject {
    struct PasswordRequest: Identifiable { let id = UUID(); let data: Data; let name: String }
    @Published var passwordRequest: PasswordRequest?
    @Published private(set) var unlockingBackup = false
    private var unlockedRestore: PendingRestore?
    struct PendingRestore: Identifiable {
        let id = UUID()
        let data: Data
        let summary: BackupValidator.Validated
    }
    @Published private(set) var integrityReport: IntegrityReport?
    @Published private(set) var checkingIntegrity = false
    @Published private(set) var entries: [BackupCatalog.Entry] = []
    @Published private(set) var preRestore: [BackupCatalog.Entry] = []
    @Published private(set) var isRestoring = false
    @Published var pending: PendingRestore?
    @Published var restoredTransactionCount: Int?
    @Published var message: String?
    @Published var error: String?
    @Published private(set) var refreshID = UUID()
    let scheduler: BackupScheduler
    private let reminders = ReminderService(client: SystemReminderClient())

    init(scheduler: BackupScheduler) { self.scheduler = scheduler; refresh() }
    var health: BackupHealth {
        let last = (entries + preRestore).max { $0.createdAt < $1.createdAt }
        let integrityDate = scheduler.defaults.object(forKey: "SaveMoney.lastIntegrityCheck") as? Date
        let bytes = (entries + preRestore).reduce(Int64(0)) { total, entry in
            total + (((try? FileManager.default.attributesOfItem(atPath: entry.url.path)[.size]) as? NSNumber)?.int64Value ?? 0)
        }
        let context = ModelContext(scheduler.exporter.container)
        return BackupHealth.evaluate(now: scheduler.clock.now, lastBackup: last.flatMap { try? BackupFile.date($0.createdAt) },
            lastBackupKind: last.map { $0.url.lastPathComponent.contains("-Auto") ? .auto : $0.url.lastPathComponent.contains("-PreRestore") ? .preRestore : .manual }, fileCount: entries.count + preRestore.count,
            totalBytes: bytes, lastExternalCopy: scheduler.lastExternalCopy,
            lastIntegrityCheck: integrityDate.map { .init(date: $0, healthy: scheduler.defaults.bool(forKey: "SaveMoney.lastIntegrityHealthy")) },
            changesSinceBackup: scheduler.changes, lastError: scheduler.lastError, transactionCount: (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0,
            encryptionEnabled: scheduler.exporter.protection.enabled, lastPasswordCheck: scheduler.exporter.protection.defaults.object(forKey: "SaveMoney.lastBackupPasswordCheck") as? Date)
    }
    var latest: URL? { entries.first?.url }
    func refresh() {
        do {
            entries = try BackupCatalog.entries(in: scheduler.exporter.directory, protection: scheduler.exporter.protection)
            preRestore = try BackupCatalog.entries(in: scheduler.exporter.directory.appendingPathComponent("PreRestore"), protection: scheduler.exporter.protection)
        } catch { self.error = "Không đọc được danh sách sao lưu." }
        refreshID = UUID()
    }
    func checkIntegrityIfDue() {
        let last = scheduler.defaults.object(forKey: "SaveMoney.lastIntegrityCheck") as? Date
        if last == nil || scheduler.clock.now.timeIntervalSince(last!) >= 7 * 86_400 { checkIntegrity() }
    }
    func checkIntegrity() {
        guard !checkingIntegrity else { return }
        checkingIntegrity = true
        Task {
            defer { checkingIntegrity = false }
            do {
                let data = try IntegrityChecker.check(container: scheduler.exporter.container, backupDirectory: nil)
                let directory = scheduler.exporter.directory
                let protection = scheduler.exporter.protection
                let files = try await Task.detached { try IntegrityChecker.checkFiles(in: directory, protection: protection) }.value
                let report = IntegrityReport(checkedAt: scheduler.clock.now, issues: data.issues + files.issues,
                    transactionCount: data.transactionCount, totalBalance: data.totalBalance, backupFilesChecked: files.checked)
                integrityReport = report
                scheduler.defaults.set(report.checkedAt, forKey: "SaveMoney.lastIntegrityCheck")
                scheduler.defaults.set(report.isHealthy, forKey: "SaveMoney.lastIntegrityHealthy")
            } catch { self.error = "Không kiểm tra được dữ liệu. Hãy thử lại; dữ liệu chưa bị thay đổi." }
        }
    }
    func backupNow() {
        do { _ = try scheduler.manual(); error = nil; message = "Đã tạo và kiểm tra bản sao lưu."; refresh() }
        catch { self.error = "Không tạo được bản sao lưu. Các bản cũ được giữ nguyên." }
    }
    func prepare(url: URL) {
        restoredTransactionCount = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            do {
                let plaintext = try scheduler.exporter.protection.plaintext(data)
                let summary = try BackupValidator.read(plaintext)
                pending = PendingRestore(data: plaintext, summary: summary)
            } catch BackupCrypto.CryptoError.keyUnavailable {
                _ = try BackupCrypto.envelope(data)
                passwordRequest = PasswordRequest(data: data, name: url.lastPathComponent)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func unlockBackup(password: String) {
        guard let request = passwordRequest, !unlockingBackup else { return }
        unlockingBackup = true
        Task {
            defer { unlockingBackup = false }
            do {
                let data = request.data
                let plaintext = try await Task.detached { try BackupCrypto.open(data, password: password) }.value
                unlockedRestore = PendingRestore(data: plaintext, summary: try BackupValidator.read(plaintext))
                error = nil; passwordRequest = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    func finishPreparedRestore() { if let unlockedRestore { pending = unlockedRestore; self.unlockedRestore = nil } }
    func restoreConfirmed(_ candidate: PendingRestore) {
        guard !isRestoring else { return }
        restoredTransactionCount = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            let restored = try BackupRestorer(container: scheduler.exporter.container, exporter: scheduler.exporter).restore(candidate.data)
            pending = nil; error = nil
            restoredTransactionCount = restored.file.summary.transactions
            message = "Đã khôi phục \(restored.file.summary.transactions) giao dịch. Số dư tất cả ví khớp bản sao lưu."
            refresh()
        } catch {
            self.error = (error as? BackupError)?.localizedDescription ?? "Khôi phục thất bại. Dữ liệu hiện tại được giữ nguyên."
        }
    }
    func sharedSuccessfully() {
        let date = scheduler.clock.now
        scheduler.defaults.set(date, forKey: BackupScheduler.externalCopyKey)
        refresh()
        Task {
            do {
                let allowed = try await reminders.externalCopyCompleted(at: date)
                message = allowed ? "Đã chép ra ngoài và đặt lại nhắc sao lưu." : "Đã chép ra ngoài. Chưa được phép gửi thông báo; hãy bật trong Cài đặt iPhone."
            } catch { self.error = "Đã chép ra ngoài, nhưng chưa đặt được thông báo nhắc." }
        }
    }
}
