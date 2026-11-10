import Foundation

protocol Clock { var now: Date { get } }
struct SystemClock: Clock { var now: Date { Date() } }

struct BackupCatalog {
    struct Entry: Identifiable {
        var id: URL { url }
        let url: URL
        let file: BackupFile
    }
    static func entries(in directory: URL) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("SaveMoney-") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let validated = try? BackupValidator.read(data) else { return nil }
                return Entry(url: url, file: validated.file)
            }.sorted {
                $0.file.createdAt == $1.file.createdAt ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.file.createdAt > $1.file.createdAt
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
    var onChange: (() -> Void)?
    private let counterKey = "SaveMoney.backupMutationCount"
    static let externalCopyKey = "SaveMoney.lastExternalCopy"

    init(exporter: BackupExporter, defaults: UserDefaults = .standard, clock: any Clock = SystemClock()) {
        self.exporter = exporter; self.defaults = defaults; self.clock = clock
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
    func restored() { defaults.set(0, forKey: counterKey); lastError = nil; onChange?() }

    @discardableResult func automatic() -> URL? {
        do {
            let captured = try exporter.capture(now: clock.now)
            let previous = try BackupCatalog.entries(in: exporter.directory).first
            if let previous {
                if previous.file.checksum == captured.checksum {
                    defaults.set(0, forKey: counterKey); lastError = nil; onChange?(); return nil
                }
                if captured.payload.isEmpty && !previous.file.payload.isEmpty { return nil }
            }
            let url = try exporter.export(kind: .auto, now: clock.now, captured: captured)
            try BackupCatalog.rotate(directory: exporter.directory)
            defaults.set(0, forKey: counterKey); lastError = nil; onChange?()
            return url
        } catch {
            lastError = "Sao lưu tự động thất bại. Hãy sao lưu lại trong Cài đặt."
            onChange?(); return nil
        }
    }
    @discardableResult func manual() throws -> URL {
        do {
            let url = try exporter.export(kind: .manual, now: clock.now)
            try BackupCatalog.rotate(directory: exporter.directory)
            lastError = nil; defaults.set(0, forKey: counterKey); onChange?(); return url
        } catch { lastError = "Sao lưu thất bại. Các bản sao lưu cũ vẫn được giữ nguyên."; onChange?(); throw error }
    }
}

extension Notification.Name {
    static let ledgerDidChange = Notification.Name("SaveMoney.ledgerDidChange")
    static let ledgerDidRestore = Notification.Name("SaveMoney.ledgerDidRestore")
}
