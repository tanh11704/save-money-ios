#if !SWIFT_PACKAGE
import Foundation
import SwiftData
import XCTest
@testable import SaveMoney

@MainActor
final class RecurringRuntimeTests: XCTestCase {
    private final class Auth: Authenticator {
        var available = true
        func authenticate(reason: String) async -> Bool { true }
        func cancel() {}
    }
    private final class Notifications: NotificationScheduling {
        var alerts: [BudgetAlert] = []
        var scheduled: (() -> Void)?
        func isAuthorized() async -> Bool { true }
        func schedule(_ alert: BudgetAlert) async throws { alerts.append(alert); scheduled?() }
    }
    func testUnlockGenerationCountsEveryRecordAndNotifiesOnceForWholeBatch() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let suite = "RecurringRuntimeTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        defaults.set(true, forKey: AppLockService.enabledKey)
        let context = container.mainContext, wallet = Wallet(name: "A"), category = SaveMoney.Category(name: "Chi", kind: .expense)
        let rule = RecurringRule(); rule.wallet = wallet; rule.category = category; rule.amount = 120_000; rule.frequencyRaw = "daily"
        rule.startDate = LocalCalendar.calendar.startOfDay(for: Date())
        context.insert(wallet); context.insert(category); context.insert(rule)
        try BudgetPersistence.setLimit(100_000, scope: .total, from: ReportingMonth(), context: context)
        try context.save()
        let scheduler = BackupScheduler(exporter: BackupExporter(container: container, directory: folder), defaults: defaults)
        let lock = AppLockService(authenticator: Auth(), defaults: defaults), notifications = Notifications()
        let runtime = AppRuntime(container: container, scheduler: scheduler, lock: lock,
            budgetAlerts: BudgetAlertService(scheduler: notifications, defaults: defaults))
        runtime.generateRecurring()
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()), 0)
        let sent = expectation(description: "Only the batch's two thresholds"); sent.expectedFulfillmentCount = 2
        notifications.scheduled = { sent.fulfill() }
        await lock.unlock(); runtime.generateRecurring()
        await fulfillment(of: [sent], timeout: 5)
        XCTAssertEqual(scheduler.changes, 1); XCTAssertEqual(notifications.alerts.count, 2)
        runtime.generateRecurring()
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(scheduler.changes, 1)
    }
    func testTwentyThreeGeneratedTransactionsRotateBackupAtTwenty() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let suite = "RecurringRuntimeTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let context = container.mainContext, wallet = Wallet(name: "A"), category = SaveMoney.Category(name: "Chi", kind: .expense)
        let rule = RecurringRule(); rule.wallet = wallet; rule.category = category; rule.frequencyRaw = "daily"
        rule.startDate = LocalCalendar.calendar.date(byAdding: .day, value: -22, to: LocalCalendar.calendar.startOfDay(for: Date()))!
        context.insert(wallet); context.insert(category); context.insert(rule); try context.save()
        let scheduler = BackupScheduler(exporter: BackupExporter(container: container, directory: folder), defaults: defaults)
        let runtime = AppRuntime(container: container, scheduler: scheduler, lock: AppLockService(authenticator: Auth(), defaults: defaults))
        runtime.generateRecurring()
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()), 23)
        XCTAssertEqual(scheduler.changes, 3)
        XCTAssertEqual(try BackupCatalog.entries(in: folder).count, 1)
    }
}
#endif
