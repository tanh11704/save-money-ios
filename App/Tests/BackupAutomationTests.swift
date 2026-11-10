import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias LedgerClock = SaveMoneyCore.Clock
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias LedgerClock = SaveMoney.Clock
private typealias Category = SaveMoney.Category
#endif

private final class BackupTestClock: LedgerClock { var now = Date(timeIntervalSince1970: 1_789_000_000) }

@MainActor
final class BackupAutomationTests: XCTestCase {
    @MainActor private final class Fixture {
        let container: ModelContainer
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupAutomation-\(UUID().uuidString)")
        let suite = "BackupAutomation.\(UUID().uuidString)"
        let defaults: UserDefaults
        let clock = BackupTestClock()
        var exporter: BackupExporter { BackupExporter(container: container, directory: folder) }
        init() throws {
            let schema = Schema([Wallet.self, Category.self, Transaction.self])
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            defaults = UserDefaults(suiteName: suite)!
            container.mainContext.autosaveEnabled = false
            container.mainContext.insert(Wallet(name: "Ví"))
            try container.mainContext.save()
        }
        func scheduler() -> BackupScheduler { BackupScheduler(exporter: exporter, defaults: defaults, clock: clock) }
        func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    }

    func testTwentyChangesTriggerOnceAndIdenticalChecksumSkips() async throws {
        let f = try Fixture(); defer { f.clean() }
        let scheduler = f.scheduler()
        for _ in 0..<19 { scheduler.transactionChanged() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.folder.path))
        scheduler.transactionChanged()
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder).count, 1)
        XCTAssertEqual(scheduler.changes, 0)
        XCTAssertNil(scheduler.automatic())
        for _ in 0..<20 { scheduler.transactionChanged() }
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder).count, 1)
        XCTAssertEqual(scheduler.changes, 0)
    }

    func testCounterSurvivesRestartAndFailedBackupRetries() async throws {
        let f = try Fixture(); defer { f.clean() }
        for _ in 0..<19 { f.scheduler().transactionChanged() }
        XCTAssertEqual(f.scheduler().changes, 19)
        var bad = f.exporter; bad.beforeWrite = { throw BackupError.unreadable }
        let failing = BackupScheduler(exporter: bad, defaults: f.defaults, clock: f.clock)
        failing.transactionChanged()
        XCTAssertEqual(failing.changes, 20)
        XCTAssertNotNil(failing.lastError)
        XCTAssertNotNil(f.scheduler().automatic())
        XCTAssertEqual(f.scheduler().changes, 0)
    }

    func testRotationKeepsTenAndFivePreRestoreIndependently() async throws {
        let f = try Fixture(); defer { f.clean() }
        let scheduler = f.scheduler()
        var oldest: URL?
        for _ in 0..<12 {
            let url = try scheduler.manual()
            if oldest == nil { oldest = url }
            f.clock.now.addTimeInterval(1)
        }
        for _ in 0..<7 {
            _ = try f.exporter.export(kind: .preRestore, now: f.clock.now)
            try BackupCatalog.rotate(directory: f.folder)
            f.clock.now.addTimeInterval(1)
        }
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder).count, 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(oldest).path))
        let pre = try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore"))
        XCTAssertEqual(pre.count, 5)
        for _ in 0..<12 { _ = try scheduler.manual(); f.clock.now.addTimeInterval(1) }
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore")).map(\.url), pre.map(\.url))
    }

    func testChangedDataCreatesNewAutoBackupWithoutEvictingPreRestore() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.exporter.export(kind: .preRestore, now: f.clock.now)
        let pre = try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore"))
        let scheduler = f.scheduler()
        for index in 0..<12 {
            let context = ModelContext(f.container)
            context.autosaveEnabled = false
            let wallet = try XCTUnwrap(context.fetch(FetchDescriptor<Wallet>()).first)
            wallet.name = "Ví \(index)"
            try context.save()
            XCTAssertNotNil(scheduler.automatic())
            f.clock.now.addTimeInterval(1)
        }
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder).count, 10)
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore")).map(\.url), pre.map(\.url))
    }

    func testBannerChangesOneSecondPastThresholds() async throws {
        let f = try Fixture(); defer { f.clean() }
        let scheduler = f.scheduler()
        let start = f.clock.now
        f.defaults.set(start, forKey: BackupScheduler.externalCopyKey)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 7, to: start)!
        f.clock.now.addTimeInterval(1)
        XCTAssertEqual(scheduler.status, .yellow)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 14, to: start)!
        f.clock.now.addTimeInterval(1)
        XCTAssertEqual(scheduler.status, .red)
    }

    func testEmptyDataNeverDisplacesPriorNonemptyAutoBackup() async throws {
        let f = try Fixture(); defer { f.clean() }
        let scheduler = f.scheduler()
        let prior = try XCTUnwrap(scheduler.automatic())
        let data = try Data(contentsOf: prior)
        let context = ModelContext(f.container); context.autosaveEnabled = false
        for wallet in try context.fetch(FetchDescriptor<Wallet>()) { context.delete(wallet) }
        try context.save()
        XCTAssertNil(scheduler.automatic())
        XCTAssertEqual(try Data(contentsOf: prior), data)
        XCTAssertEqual(try BackupCatalog.entries(in: f.folder).count, 1)
    }

    func testBannerThresholdsUseExternalCopyDateNotRecentAutoBackup() async throws {
        let f = try Fixture(); defer { f.clean() }
        let scheduler = f.scheduler()
        XCTAssertEqual(scheduler.status, .never)
        f.defaults.set(f.clock.now, forKey: BackupScheduler.externalCopyKey)
        XCTAssertEqual(scheduler.status, .current)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 7, to: f.clock.now)!
        XCTAssertEqual(scheduler.status, .current)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 1, to: f.clock.now)!
        XCTAssertEqual(scheduler.status, .yellow)
        _ = try scheduler.manual()
        XCTAssertEqual(scheduler.status, .yellow)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 6, to: f.clock.now)!
        XCTAssertEqual(scheduler.status, .yellow)
        f.clock.now = LocalCalendar.calendar.date(byAdding: .day, value: 1, to: f.clock.now)!
        XCTAssertEqual(scheduler.status, .red)
    }
}

@MainActor
private final class FakeReminderClient: ReminderClient {
    var permission = true
    var removed: [[String]] = []
    var reminders: [BackupReminder] = []
    func requestPermission() async throws -> Bool { permission }
    func remove(ids: [String]) { removed.append(ids); reminders.removeAll { ids.contains($0.id) } }
    func add(_ reminder: BackupReminder) async throws { reminders.append(reminder) }
}

@MainActor
final class ReminderServiceTests: XCTestCase {
    func testShareResetsFourteenTwentyOneTwentyEightDaysWithGenericContent() async throws {
        let clock = BackupTestClock()
        let client = FakeReminderClient()
        let service = ReminderService(client: client, clock: clock)
        let authorizedFirst = try await service.externalCopyCompleted()
        XCTAssertTrue(authorizedFirst)
        XCTAssertEqual(client.reminders.count, 3)
        let original = client.reminders
        for (reminder, days) in zip(original, [14, 21, 28]) {
            XCTAssertEqual(reminder.date, LocalCalendar.calendar.date(byAdding: .day, value: days, to: clock.now))
            XCTAssertEqual(reminder.body, "Chép file backup sang iCloud Drive")
        }
        clock.now.addTimeInterval(86_400)
        let authorizedAgain = try await service.externalCopyCompleted()
        XCTAssertTrue(authorizedAgain)
        XCTAssertEqual(client.removed.count, 2)
        XCTAssertEqual(client.reminders.count, 3)
        XCTAssertNotEqual(client.reminders.first?.date, original.first?.date)
        XCTAssertEqual(Set(client.reminders.map(\.id)), Set(ReminderService.ids))
    }
    func testPermissionDeniedCancelsPendingWithoutAddingRequests() async throws {
        let client = FakeReminderClient(); client.permission = false
        let allowed = try await ReminderService(client: client).externalCopyCompleted()
        XCTAssertFalse(allowed)
        XCTAssertEqual(client.removed, [ReminderService.ids]); XCTAssertTrue(client.reminders.isEmpty)
    }
}
