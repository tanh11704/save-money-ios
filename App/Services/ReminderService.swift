import Foundation
import UserNotifications

struct BackupReminder: Equatable {
    let id: String
    let date: Date
    let body: String
}

@MainActor
protocol ReminderClient {
    func requestPermission() async throws -> Bool
    func remove(ids: [String])
    func add(_ reminder: BackupReminder) async throws
}

@MainActor
final class SystemReminderClient: ReminderClient {
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func remove(ids: [String]) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids) }
    func add(_ reminder: BackupReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Nhắc sao lưu SaveMoney"
        content.body = reminder.body
        content.sound = .default
        let components = LocalCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        var dated = components; dated.calendar = LocalCalendar.calendar; dated.timeZone = LocalCalendar.calendar.timeZone
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: reminder.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dated, repeats: false)))
    }
}

@MainActor
struct ReminderService {
    static let ids = [14, 21, 28].map { "SaveMoney.backupReminder.\($0)" }
    let client: any ReminderClient
    var clock: any Clock = SystemClock()

    func externalCopyCompleted(at date: Date? = nil) async throws -> Bool {
        let authorized = try await client.requestPermission()
        client.remove(ids: Self.ids)
        guard authorized else { return false }
        let date = date ?? clock.now
        for (index, days) in [14, 21, 28].enumerated() {
            let due = LocalCalendar.calendar.date(byAdding: .day, value: days, to: date)!
            try await client.add(BackupReminder(id: Self.ids[index], date: due, body: "Chép file backup sang iCloud Drive"))
        }
        return true
    }
}
