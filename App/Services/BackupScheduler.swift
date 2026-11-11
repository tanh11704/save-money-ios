import Foundation

protocol Clock { var now: Date { get } }
struct SystemClock: Clock { var now: Date { Date() } }

struct BackupCatalog {
    struct Entry: Identifiable {
        var id: URL { url }
        let url: URL
        let file: BackupFile?
        let createdAt: Int64
        let encrypted: Bool
    }
    static func entries(in directory: URL, protection: BackupProtection = BackupProtection()) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["json", "savemoney"].contains($0.pathExtension) && $0.lastPathComponent.hasPrefix("SaveMoney-") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                if BackupCrypto.isEncrypted(data) {
                    guard let envelope = try? BackupCrypto.envelope(data) else { return nil }
                    let file = try? BackupValidator.decode(data, protection: protection).file
                    return Entry(url: url, file: file, createdAt: envelope.header.createdAt, encrypted: true)
                }
                guard let file = try? BackupValidator.read(data).file else { return nil }
                return Entry(url: url, file: file, createdAt: file.createdAt, encrypted: false)
            }.sorted {
                $0.createdAt == $1.createdAt ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.createdAt > $1.createdAt
            }
    }

    static func rotate(directory: URL) throws {
        for (folder, limit) in [(directory, 10), (directory.appendingPathComponent("PreRestore"), 5)] {
            for entry in try entries(in: folder).dropFirst(limit) { try FileManager.default.removeItem(at: entry.url) }
        }
    }
}

@MainActor
final class BackupScheduler {
    enum Status: Equatable { case never, current, yellow, red }
    let exporter: BackupExporter
    let defaults: UserDefaults
    let clock: any Clock
    private(set) var lastError: String?
    var onAutomaticFailure: ((Int) -> Void)?
    var consecutiveFailures: Int { defaults.integer(forKey: "SaveMoney.backupFailures") }
    var onChange: (() -> Void)?
    private let counterKey = "SaveMoney.backupMutationCount"
    static let externalCopyKey = "SaveMoney.lastExternalCopy"

    init(exporter: BackupExporter, defaults: UserDefaults = .standard, clock: any Clock = SystemClock()) {
        self.exporter = exporter; self.defaults = defaults; self.clock = clock
        lastError = defaults.string(forKey: "SaveMoney.lastBackupError")
    }
    var changes: Int { defaults.integer(forKey: counterKey) }
    var lastExternalCopy: Date? { defaults.object(forKey: Self.externalCopyKey) as? Date }
    var externalCopyAge: Int? {
        lastExternalCopy.map { max(0, LocalCalendar.calendar.dateComponents([.day], from: $0, to: clock.now).day ?? 0) }
    }
    var status: Status {
        guard let last = lastExternalCopy else { return .never }
        if clock.now > LocalCalendar.calendar.date(byAdding: .day, value: 14, to: last)! { return .red }
        if clock.now > LocalCalendar.calendar.date(byAdding: .day, value: 7, to: last)! { return .yellow }
        return .current
    }
    func transactionChanged() {
        defaults.set(changes + 1, forKey: counterKey)
        if changes >= 20 { _ = automatic() }
    }
    func restored() { defaults.set(0, forKey: counterKey); lastError = nil; defaults.removeObject(forKey: "SaveMoney.lastBackupError"); defaults.set(0, forKey: "SaveMoney.backupFailures"); onChange?() }

    @discardableResult func automatic() -> URL? {
        do {
            _ = try exporter.protection.exportKey()
            let captured = try exporter.capture(now: clock.now)
            let previous = try BackupCatalog.entries(in: exporter.directory, protection: exporter.protection).first
            if let previous {
                if previous.file?.checksum == captured.checksum {
                    defaults.set(0, forKey: counterKey); lastError = nil; defaults.removeObject(forKey: "SaveMoney.lastBackupError"); defaults.set(0, forKey: "SaveMoney.backupFailures"); onChange?(); return nil
                }
                if captured.payload.isEmpty && (previous.file?.payload.isEmpty != true) { return nil }
            }
            let url = try exporter.export(kind: .auto, now: clock.now, captured: captured)
            try BackupCatalog.rotate(directory: exporter.directory)
            defaults.set(0, forKey: counterKey); lastError = nil; defaults.removeObject(forKey: "SaveMoney.lastBackupError"); defaults.set(0, forKey: "SaveMoney.backupFailures"); onChange?()
            return url
        } catch {
            lastError = "Sao lưu tự động thất bại. Hãy sao lưu lại trong Cài đặt."
            defaults.set(lastError, forKey: "SaveMoney.lastBackupError")
            defaults.set(consecutiveFailures + 1, forKey: "SaveMoney.backupFailures")
            onAutomaticFailure?(consecutiveFailures)
            onChange?(); return nil
        }
    }
    @discardableResult func manual() throws -> URL {
        do {
            let url = try exporter.export(kind: .manual, now: clock.now)
            try BackupCatalog.rotate(directory: exporter.directory)
            lastError = nil; defaults.removeObject(forKey: "SaveMoney.lastBackupError"); defaults.set(0, forKey: "SaveMoney.backupFailures"); defaults.set(0, forKey: counterKey); onChange?(); return url
        } catch { lastError = "Sao lưu thất bại. Các bản sao lưu cũ vẫn được giữ nguyên."; defaults.set(lastError, forKey: "SaveMoney.lastBackupError"); onChange?(); throw error }
    }
}

extension Notification.Name {
    static let recurringRulesDidChange = Notification.Name("SaveMoney.recurringRulesDidChange")
    static let ledgerDidChange = Notification.Name("SaveMoney.ledgerDidChange")
    static let ledgerDidRestore = Notification.Name("SaveMoney.ledgerDidRestore")
}
