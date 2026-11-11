import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class BackupRecurringTests: XCTestCase {
    private func fixture(_ version: Int) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "golden-v\(version)", withExtension: "json", subdirectory: "Fixtures")))
    }
    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
    func testGoldenV3RoundTripAndV2ClearsRules() async throws {
        let container = try container(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = BackupExporter(container: container, directory: folder), restorer = BackupRestorer(container: container, exporter: exporter)
        let data = try fixture(3), original = try BackupValidator.read(data).file
        XCTAssertEqual(try BackupFile.digest(original.payload), original.checksum)
        _ = try restorer.restore(data)
        let captured = try exporter.capture(now: BackupFile.date(original.createdAt))
        XCTAssertEqual(captured.payload, original.payload)
        XCTAssertEqual(captured.summary, original.summary)
        XCTAssertEqual(try RecurringService.generateDue(now: Date(), container: container).created, 0)
        _ = try restorer.restore(fixture(2))
        let restored = try exporter.capture()
        XCTAssertTrue(restored.payload.recurringRules.isEmpty)
        XCTAssertTrue(restored.payload.transactions.allSatisfy { $0.recurrenceKey == nil })
        XCTAssertEqual(restored.payload.budgets.count, 2)
    }
    func testInvalidReferencesCyclesAndDuplicateKeysRejectedWithoutWrites() async throws {
        let original = try BackupValidator.read(fixture(3)).file
        var file = original
        file.payload.recurringRules[0].walletId = UUID().uuidString
        file.checksum = try BackupFile.digest(file.payload); XCTAssertThrowsError(try BackupValidator.validate(file))
        file = original; file.payload.recurringRules[0].interval = 0
        file.checksum = try BackupFile.digest(file.payload); XCTAssertThrowsError(try BackupValidator.validate(file))
        file = original; file.payload.recurringRules[0].endDate = 0
        file.checksum = try BackupFile.digest(file.payload); XCTAssertThrowsError(try BackupValidator.validate(file))
        file = original; var duplicate = file.payload.transactions[0]; duplicate.id = UUID().uuidString
        file.payload.transactions.append(duplicate); file.summary.transactions += 1
        file.checksum = try BackupFile.digest(file.payload); XCTAssertThrowsError(try BackupValidator.validate(file))
        file = original; file.payload.recurringRules[0].amount += 1
        XCTAssertThrowsError(try BackupValidator.validate(file)) { XCTAssertEqual($0 as? BackupError, .checksum) }
    }
    func testRestorePreservesCursorAndKeysSoNextGenerationDoesNotDuplicate() async throws {
        let container = try container(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = container.mainContext
        let wallet = Wallet(name: "A"), category = SaveMoneyCategory(name: "Chi", kind: .expense), rule = RecurringRule()
        rule.wallet = wallet; rule.category = category; rule.amount = 100
        rule.startDate = LocalCalendar.calendar.startOfDay(for: Date())
        context.insert(wallet); context.insert(category); context.insert(rule); try context.save()
        XCTAssertEqual(try RecurringService.generateDue(now: Date(), container: container).created, 1)
        let exporter = BackupExporter(container: container, directory: folder), file = try exporter.capture()
        _ = try BackupRestorer(container: container, exporter: exporter).restore(BackupFile.encoder().encode(file))
        XCTAssertEqual(try RecurringService.generateDue(now: Date(), container: container).created, 0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()), 1)
    }
    func testRestoreFailureRollsBackRecurringRulesAndTransactionKeys() async throws {
        let container = try container(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = BackupExporter(container: container, directory: folder)
        var restorer = BackupRestorer(container: container, exporter: exporter)
        _ = try restorer.restore(fixture(3))
        let now = Date(), original = try exporter.capture(now: now)
        restorer.checkpoint = { _ in throw BackupError.balances }
        XCTAssertThrowsError(try restorer.restore(fixture(2)))
        XCTAssertEqual(try exporter.capture(now: now), original)
    }

}
#if SWIFT_PACKAGE
private typealias SaveMoneyCategory = SaveMoneyCore.Category
#else
private typealias SaveMoneyCategory = SaveMoney.Category
#endif
