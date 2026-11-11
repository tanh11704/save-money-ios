import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class BackupBudgetTests: XCTestCase {
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
    func testGoldenV2AndRoundTripIncludesArchivedRules() async throws {
        let original = try fixture(2), validated = try BackupValidator.read(original)
        XCTAssertEqual(validated.file.payload.budgets.count, 2)
        XCTAssertEqual(try BackupFile.digest(validated.file.payload), validated.file.checksum)
        let container = try container()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = BackupExporter(container: container, directory: folder)
        let restorer = BackupRestorer(container: container, exporter: exporter)
        _ = try restorer.restore(original)
        let captured = try exporter.capture(now: BackupFile.date(validated.file.createdAt))
        XCTAssertEqual(captured.payload, validated.file.payload)
        XCTAssertEqual(captured.summary, validated.file.summary)
        XCTAssertEqual(captured.payload.budgets.map(\.isArchived), [false, true])
        _ = try restorer.restore(fixture(1))
        let v1Restored = try exporter.capture()
        XCTAssertTrue(v1Restored.payload.budgets.isEmpty)
        let v1 = try BackupValidator.read(fixture(1)).file
        XCTAssertEqual(v1Restored.payload.wallets, v1.payload.wallets)
        XCTAssertEqual(v1Restored.payload.categories, v1.payload.categories)
        XCTAssertEqual(v1Restored.payload.transactions, v1.payload.transactions)
        XCTAssertEqual(v1Restored.summary.expectedBalances, v1.summary.expectedBalances)
    }
    func testBudgetTamperingAndDanglingCategoryDoNotChangeLedger() async throws {
        let container = try container()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = BackupExporter(container: container, directory: folder)
        let restorer = BackupRestorer(container: container, exporter: exporter)
        _ = try restorer.restore(fixture(2))
        let date = Date(), before = try exporter.capture(now: date)
        var file = before
        file.payload.budgets[0].limit += 1
        XCTAssertThrowsError(try BackupValidator.validate(file)) { XCTAssertEqual($0 as? BackupError, .checksum) }
        file = before; file.payload.budgets[1].categoryID = UUID().uuidString
        file.checksum = try BackupFile.digest(file.payload)
        XCTAssertThrowsError(try restorer.restore(BackupFile.encoder().encode(file)))
        XCTAssertEqual(try exporter.capture(now: date), before)
        file = before; file.payload.budgets[0].startMonth = 13
        file.checksum = try BackupFile.digest(file.payload)
        XCTAssertThrowsError(try BackupValidator.validate(file))
    }
    func testFailedRestoreRollsBackBudgetDeletion() async throws {
        let container = try container()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = BackupExporter(container: container, directory: folder)
        var restorer = BackupRestorer(container: container, exporter: exporter)
        _ = try restorer.restore(fixture(2))
        let now = Date(), before = try exporter.capture(now: now)
        restorer.checkpoint = { _ in throw BackupError.balances }
        XCTAssertThrowsError(try restorer.restore(fixture(1)))
        XCTAssertEqual(try exporter.capture(now: now), before)
    }
}
