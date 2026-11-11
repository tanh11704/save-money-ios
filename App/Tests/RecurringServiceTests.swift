import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

@MainActor
final class RecurringServiceTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { LocalCalendar.calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    private func fixture() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let a = Wallet(name: "A", openingBalance: 1_000), b = Wallet(name: "B"), category = Category(name: "Chi", kind: .expense)
        let rule = RecurringRule(); rule.amount = 100; rule.wallet = a; rule.category = category; rule.startDate = date(2026, 8, 5)
        context.insert(a); context.insert(b); context.insert(category); context.insert(rule); try context.save()
        return container
    }
    private func records(_ container: ModelContainer) throws -> [Transaction] { try ModelContext(container).fetch(FetchDescriptor<Transaction>()) }
    func testCatchupIdempotenceDeletedOccurrenceAndRewoundCursor() async throws {
        let container = try fixture(), now = date(2026, 11, 5)
        XCTAssertEqual(try RecurringService.generateDue(now: now, container: container).created, 4)
        XCTAssertEqual(try RecurringService.generateDue(now: now, container: container).created, 0)
        let context = ModelContext(container), transactions = try context.fetch(FetchDescriptor<Transaction>())
        context.delete(transactions[0]); try context.save()
        XCTAssertEqual(try RecurringService.generateDue(now: now, container: container).created, 0)
        // Rewind while keeping all remaining keys: only the explicitly rewound,
        // deleted occurrence can be missing. A normal deletion never rewinds.
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringRule>()).first)
        rule.generatedThrough = date(2026, 10, 5); try context.save()
        let existingNovember = try records(container).contains { $0.date == now }
        XCTAssertEqual(try RecurringService.generateDue(now: now, container: container).created, existingNovember ? 0 : 1)
        let keys = try records(container).compactMap(\.recurrenceKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
    func testArchiveSkipDoesNotAdvanceAndRestorationCatchesUp() async throws {
        let container = try fixture(), context = ModelContext(container)
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringRule>()).first)
        rule.wallet?.isArchived = true; try context.save()
        let result = try RecurringService.generateDue(now: date(2026, 11, 5), container: container)
        XCTAssertEqual(result.created, 0); XCTAssertEqual(result.skipped.count, 1)
        XCTAssertNil(try ModelContext(container).fetch(FetchDescriptor<RecurringRule>()).first?.generatedThrough)
        rule.wallet?.isArchived = false; try context.save()
        XCTAssertEqual(try RecurringService.generateDue(now: date(2026, 11, 5), container: container).created, 4)
    }
    func testPauseEndDateTransferBalancesAndRollback() async throws {
        let container = try fixture(), context = ModelContext(container)
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringRule>()).first)
        rule.isPaused = true; try context.save()
        XCTAssertEqual(try RecurringService.generateDue(now: date(2026, 11, 5), container: container).created, 0)
        rule.isPaused = false; rule.endDate = date(2026, 9, 5); rule.kindRaw = "transfer"; rule.category = nil
        rule.toWallet = try context.fetch(FetchDescriptor<Wallet>()).first { $0.name == "B" }; try context.save()
        XCTAssertThrowsError(try RecurringService.generateDue(now: date(2026, 11, 5), container: container, beforeSave: { _ in throw BackupError.balances }))
        XCTAssertTrue(try records(container).isEmpty)
        XCTAssertNil(try ModelContext(container).fetch(FetchDescriptor<RecurringRule>()).first?.generatedThrough)
        XCTAssertEqual(try RecurringService.generateDue(now: date(2026, 11, 5), container: container).created, 2)
        let fresh = ModelContext(container), wallets = try fresh.fetch(FetchDescriptor<Wallet>()), transactions = try records(container)
        XCTAssertEqual(try BalanceCalculator.balance(for: XCTUnwrap(wallets.first { $0.name == "A" }), transactions: transactions), 800)
        XCTAssertEqual(try BalanceCalculator.balance(for: XCTUnwrap(wallets.first { $0.name == "B" }), transactions: transactions), 200)
        XCTAssertEqual(try BalanceCalculator.totalBalance(wallets: wallets, transactions: transactions), 1_000)
    }
    func testBatchLimitAndEditingSchedulePreservesCursor() async throws {
        let container = try fixture(), context = ModelContext(container)
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringRule>()).first)
        rule.frequencyRaw = "daily"; rule.startDate = date(2020, 1, 1); try context.save()
        let result = try RecurringService.generateDue(now: date(2026, 11, 5), container: container)
        XCTAssertEqual(result.created, 400); XCTAssertTrue(result.hasMore)
        let fresh = ModelContext(container), current = try XCTUnwrap(fresh.fetch(FetchDescriptor<RecurringRule>()).first)
        var draft = try XCTUnwrap(current.draft); let cursor = current.generatedThrough
        draft.frequency = .monthly; draft.startDate = date(2019, 1, 1)
        try RecurringPersistence(container: container).save(draft, editing: current.id)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<RecurringRule>()).first?.generatedThrough, cursor)
    }
}
