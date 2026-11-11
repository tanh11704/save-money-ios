import XCTest
import Foundation
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
@MainActor
final class BackupFailureNotifierTests: XCTestCase {
    private final class Client: ReminderClient {
        var reminders: [BackupReminder] = []
        func requestPermission() async throws -> Bool { true }
        func remove(ids: [String]) {}
        func add(_ reminder: BackupReminder) async throws { reminders.append(reminder) }
    }
    func testConsecutiveFailuresAlertOnlyOncePerLocalDay() async {
        let suite = "FailureNotifier.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = Client(), service = BackupFailureNotifier(client: client, defaults: defaults), now = Date()
        await service.notify(consecutiveFailures: 1, now: now); XCTAssertTrue(client.reminders.isEmpty)
        await service.notify(consecutiveFailures: 2, now: now)
        await service.notify(consecutiveFailures: 3, now: now); XCTAssertEqual(client.reminders.count, 1)
        await service.notify(consecutiveFailures: 4, now: LocalCalendar.calendar.date(byAdding: .day, value: 1, to: now)!)
        XCTAssertEqual(client.reminders.count, 2)
    }
}
