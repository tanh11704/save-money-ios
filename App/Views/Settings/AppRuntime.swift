import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AppRuntime: ObservableObject {
    let container: ModelContainer
    let scheduler: BackupScheduler
    let lock: AppLockService
    let settings: BackupScreenStore
    private var observers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(container: ModelContainer) {
        self.container = container
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exporter = BackupExporter(container: container, directory: documents.appendingPathComponent("Backups", isDirectory: true))
        scheduler = BackupScheduler(exporter: exporter)
        lock = AppLockService(authenticator: DeviceAuthenticator())
        settings = BackupScreenStore(scheduler: scheduler)
        scheduler.onChange = { [weak settings] in settings?.refresh() }
        observers.append(NotificationCenter.default.addObserver(forName: .ledgerDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let source = notification.object as? ModelContainer, source === container else { return }
            let isTransaction = notification.userInfo?["transaction"] as? Bool == true
            MainActor.assumeIsolated {
                if isTransaction { self?.scheduler.transactionChanged() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .ledgerDidRestore, object: nil, queue: .main) { [weak self] notification in
            guard let source = notification.object as? ModelContainer, source === container else { return }
            MainActor.assumeIsolated { self?.scheduler.restored(); self?.settings.refresh() }
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func enteredBackground() {
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
    struct PendingRestore: Identifiable {
        let id = UUID()
        let data: Data
        let summary: BackupValidator.Validated
    }
    @Published private(set) var entries: [BackupCatalog.Entry] = []
    @Published private(set) var preRestore: [BackupCatalog.Entry] = []
    @Published var pending: PendingRestore?
    @Published var message: String?
    @Published var error: String?
    @Published private(set) var refreshID = UUID()
    let scheduler: BackupScheduler
    private let reminders = ReminderService(client: SystemReminderClient())

    init(scheduler: BackupScheduler) { self.scheduler = scheduler; refresh() }
    var latest: URL? { entries.first?.url }
    func refresh() {
        do {
            entries = try BackupCatalog.entries(in: scheduler.exporter.directory)
            preRestore = try BackupCatalog.entries(in: scheduler.exporter.directory.appendingPathComponent("PreRestore"))
        } catch { self.error = "Không đọc được danh sách sao lưu." }
        refreshID = UUID()
    }
    func backupNow() {
        do { _ = try scheduler.manual(); error = nil; message = "Đã tạo và kiểm tra bản sao lưu."; refresh() }
        catch { self.error = "Không tạo được bản sao lưu. Các bản cũ được giữ nguyên." }
    }
    func prepare(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupValidator.read(data)
            pending = PendingRestore(data: data, summary: summary)
            error = nil
        } catch { self.error = (error as? BackupError)?.localizedDescription ?? "Không đọc được file sao lưu." }
    }
    func restoreConfirmed(_ candidate: PendingRestore) {
        do {
            let restored = try BackupRestorer(container: scheduler.exporter.container, exporter: scheduler.exporter).restore(candidate.data)
            pending = nil; error = nil
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
