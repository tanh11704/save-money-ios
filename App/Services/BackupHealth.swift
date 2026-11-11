import Foundation

struct BackupHealth: Equatable {
    enum Level { case good, attention, critical }
    struct Integrity: Equatable { let date: Date; let healthy: Bool }
    let level: Level
    let lastBackup: Date?
    let lastBackupKind: BackupExporter.Kind?
    let fileCount: Int
    let totalBytes: Int64
    let lastExternalCopy: Date?
    let lastIntegrityCheck: Integrity?
    let changesSinceBackup: Int
    let lastError: String?
    let reasons: [String]
    var title: String { level == .good ? "Tốt" : level == .attention ? "Cần chú ý" : "Nguy hiểm" }

    static func evaluate(now: Date, lastBackup: Date?, lastBackupKind: BackupExporter.Kind? = nil,
                         fileCount: Int, totalBytes: Int64 = 0, lastExternalCopy: Date?, lastIntegrityCheck: Integrity?,
                         changesSinceBackup: Int, lastError: String?, transactionCount: Int,
                         encryptionEnabled: Bool = false, lastPasswordCheck: Date? = nil) -> BackupHealth {
        var critical: [String] = [], attention: [String] = []
        func older(_ date: Date, days: Int) -> Bool { now > LocalCalendar.calendar.date(byAdding: .day, value: days, to: date)! }
        if let lastBackup {
            if older(lastBackup, days: 14) { critical.append("Backup gần nhất đã quá 14 ngày.") }
            else if older(lastBackup, days: 7) { attention.append("Backup gần nhất đã quá 7 ngày.") }
        } else { critical.append("Chưa có bản sao lưu.") }
        if let lastError { critical.append(lastError) }
        if let lastIntegrityCheck {
            if !lastIntegrityCheck.healthy { critical.append("Kiểm tra toàn vẹn gần nhất có lỗi.") }
            if older(lastIntegrityCheck.date, days: 30) { attention.append("Đã quá 30 ngày chưa kiểm tra dữ liệu.") }
        } else { attention.append("Chưa kiểm tra toàn vẹn dữ liệu.") }
        if let lastExternalCopy {
            if older(lastExternalCopy, days: 14) { attention.append("Đã quá 14 ngày chưa chép bản sao lưu ra ngoài.") }
        } else if transactionCount > 50 { critical.append("Chưa từng chép ra ngoài và đã có trên 50 giao dịch.") }
        if changesSinceBackup > 20 { attention.append("Có hơn 20 thay đổi chưa sao lưu.") }
        if encryptionEnabled && (lastPasswordCheck.map { older($0, days: 90) } ?? true) { attention.append("Hãy kiểm tra lại mật khẩu backup (mỗi 90 ngày).") }
        return BackupHealth(level: !critical.isEmpty ? .critical : !attention.isEmpty ? .attention : .good,
            lastBackup: lastBackup, lastBackupKind: lastBackupKind, fileCount: fileCount, totalBytes: totalBytes,
            lastExternalCopy: lastExternalCopy, lastIntegrityCheck: lastIntegrityCheck, changesSinceBackup: changesSinceBackup,
            lastError: lastError, reasons: critical + attention)
    }
}
