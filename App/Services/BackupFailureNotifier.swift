import Foundation

@MainActor
final class BackupFailureNotifier {
    private let client: any ReminderClient
    private let defaults: UserDefaults
    private var inFlight = false
    init(client: any ReminderClient, defaults: UserDefaults = .standard) { self.client = client; self.defaults = defaults }
    func notify(consecutiveFailures: Int, now: Date) async {
        guard consecutiveFailures >= 2, !inFlight else { return }
        let day = LocalCalendar.calendar.startOfDay(for: now)
        guard defaults.object(forKey: "SaveMoney.lastBackupFailureAlert") as? Date != day else { return }
        inFlight = true; defer { inFlight = false }
        do {
            try await client.add(BackupReminder(id: "SaveMoney.backupFailure", date: now.addingTimeInterval(1), body: "Sao lưu tự động thất bại liên tiếp. Mở SaveMoney để kiểm tra và sao lưu lại."))
            defaults.set(day, forKey: "SaveMoney.lastBackupFailureAlert")
        } catch { /* The Settings error remains visible even if notifications fail. */ }
    }
}
