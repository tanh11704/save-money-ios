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
final class BackupTests: XCTestCase {
    private let fixed = Date(timeIntervalSince1970: 1_789_000_000)
    private enum Injected: Error { case failure }
    @MainActor private final class Fixture {
        let container: ModelContainer
        let folder: URL
        let suite = "BackupTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var exporter: BackupExporter { BackupExporter(container: container, directory: folder) }
        init() throws {
            let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            container.mainContext.autosaveEnabled = false
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)").appendingPathComponent("Backups")
            defaults = UserDefaults(suiteName: suite)!
        }
        func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        func seed() throws {
            let a = Wallet(name: "Tiền mặt", openingBalance: 999_999_999_998)
            let b = Wallet(name: "Ngân hàng", openingBalance: -200, kind: .bank)
            let expense = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
            let income = Category(name: "Lương", kind: .income)
            a.isArchived = true; expense.isArchived = true
            [a, b].forEach { $0.createdAt = Date(timeIntervalSince1970: 1_789_000_000); container.mainContext.insert($0) }
            [expense, income].forEach { container.mainContext.insert($0) }
            let records = [Transaction(amount: 123, kind: .expense, wallet: a, category: expense),
                           Transaction(amount: 999_999_999_999, kind: .income, wallet: b, category: income),
                           Transaction(amount: 50_000, kind: .transfer, wallet: a, toWallet: b)]
            for record in records { record.date = Date(timeIntervalSince1970: 1_789_000_000); record.note = "Dữ liệu mẫu"; container.mainContext.insert(record) }
            try container.mainContext.save()
        }
        func bytes(_ file: BackupFile) throws -> Data { try BackupFile.encoder().encode(file) }
        func current() throws -> BackupFile { try exporter.capture(now: Date(timeIntervalSince1970: 1_789_000_000)) }
        func restorer() -> BackupRestorer { BackupRestorer(container: container, exporter: exporter, defaults: defaults) }
    }

    func testStoreConfigurationIsOutsideSharedDocuments() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let configured = ModelConfiguration(schema: schema).url.standardizedFileURL
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL
        XCTAssertFalse(configured.path.hasPrefix(documents.path + "/"))
        XCTAssertEqual(configured.lastPathComponent, "default.store")
    }

    func testGoldenFixtureIsValidAndCanonicalChecksumIsStable() async throws {
        #if SWIFT_PACKAGE
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden-v1", withExtension: "json", subdirectory: "Fixtures"))
        #else
        let url = try XCTUnwrap(Bundle(for: BackupTests.self).url(forResource: "golden-v1", withExtension: "json", subdirectory: "Fixtures"))
        #endif
        let data = try Data(contentsOf: url)
        let validated = try BackupValidator.read(data)
        XCTAssertEqual(validated.totalBalance, 123_456_790_012)
        XCTAssertEqual(try BackupFile.digest(validated.file.payload), validated.file.checksum)
        XCTAssertEqual(try BackupValidator.read(BackupFile.encoder().encode(validated.file)).file, validated.file)
        let raw = String(decoding: try BackupFile.encoder().encode(validated.file.payload), as: UTF8.self)
        XCTAssertTrue(raw.contains("\"toWalletId\":null"))
    }

    func testExportCreatesFolderAndReadBackPreservesLargeIntegersAndBalances() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let url = try f.exporter.export(kind: .manual, now: fixed)
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-Manual.json"))
        let read = try BackupValidator.read(Data(contentsOf: url))
        XCTAssertEqual(read.file, try f.current())
        XCTAssertEqual(read.file.payload.transactions.map(\.amount).max(), 999_999_999_999)
        XCTAssertEqual(read.file.summary.expectedBalances, try BackupValidator.expectedBalances(BackupValidator.graph(read.file.payload)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).filter { $0.hasSuffix("tmp") }.count, 0)
    }

    func testExportFailureCleansTempAndPreservesPriorBackup() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let prior = try f.exporter.export(kind: .manual, now: fixed)
        let bytes = try Data(contentsOf: prior)
        var broken = f.exporter
        broken.afterWrite = { _ in throw Injected.failure }
        XCTAssertThrowsError(try broken.export(kind: .manual, now: fixed))
        XCTAssertEqual(try Data(contentsOf: prior), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.folder.path), [prior.lastPathComponent])
    }

    func testCorruptedTempIsNeverPromoted() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        var exporter = f.exporter
        exporter.afterWrite = { try Data("bad".utf8).write(to: $0) }
        XCTAssertThrowsError(try exporter.export(kind: .manual, now: fixed))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).isEmpty)
    }

    func testSameSecondExportsNeverOverwrite() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let a = try f.exporter.export(kind: .manual, now: fixed)
        let original = try Data(contentsOf: a)
        let b = try f.exporter.export(kind: .manual, now: fixed)
        XCTAssertNotEqual(a, b); XCTAssertEqual(try Data(contentsOf: a), original)
    }

    func testRoundTripComparesEveryWalletCategoryTransactionAndBalance() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        let data = try f.bytes(original)
        // Explicitly clear the ledger as required by the round-trip test.
        let context = ModelContext(f.container)
        context.autosaveEnabled = false
        for record in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Wallet>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Category>()) { context.delete(record) }
        try context.save()
        f.defaults.set("stale", forKey: "SaveMoney.recentSelection.expense.wallet")
        _ = try f.restorer().restore(data, now: fixed)
        let after = try f.current()
        XCTAssertEqual(after.payload, original.payload) // Codable records compare every field.
        XCTAssertEqual(after.summary, original.summary)
        XCTAssertEqual(after.checksum, original.checksum)
        XCTAssertNil(f.defaults.object(forKey: "SaveMoney.recentSelection.expense.wallet"))
        XCTAssertTrue(f.defaults.bool(forKey: DefaultDataSeeder.marker))
    }

    func testReplacingNonemptyLedgerAndPreRestorePreserveOriginal() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let old = try f.current()
        let blank = BackupFile(createdAt: 0, appVersion: "1", checksum: try BackupFile.digest(.init(wallets: [], categories: [], transactions: [])),
            summary: .init(wallets: 0, categories: 0, transactions: 0, expectedBalances: [:]), payload: .init(wallets: [], categories: [], transactions: []))
        _ = try f.restorer().restore(f.bytes(blank), now: fixed)
        XCTAssertTrue(try f.current().payload.isEmpty)
        let backups = try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore"))
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.file.payload, old.payload)
    }

    func testNonemptyReplacementCommitsOnlyIncomingGraph() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        var incoming = original
        incoming.payload.wallets[0].name = "Ví khôi phục"
        incoming.payload.wallets[0].openingBalance = 12_345
        for index in incoming.payload.transactions.indices { incoming.payload.transactions[index].note = "Từ file" }
        incoming.checksum = try BackupFile.digest(incoming.payload)
        incoming.summary.expectedBalances = try BackupValidator.expectedBalances(BackupValidator.graph(incoming.payload))
        _ = try f.restorer().restore(f.bytes(incoming), now: fixed)
        let actual = try f.current()
        XCTAssertEqual(actual.payload, incoming.payload)
        XCTAssertEqual(actual.summary, incoming.summary)
        let pre = try BackupCatalog.entries(in: f.folder.appendingPathComponent("PreRestore"))
        XCTAssertEqual(pre.first?.file.payload, original.payload)
    }

    func testChecksumTamperAndFutureVersionRejectWithoutMutation() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        var tampered = original; tampered.payload.wallets[0].name += "x"
        XCTAssertThrowsError(try f.restorer().restore(f.bytes(tampered))) { XCTAssertEqual($0 as? BackupError, .checksum) }
        var future = original; future.schemaVersion = 4
        XCTAssertThrowsError(try f.restorer().restore(f.bytes(future))) { XCTAssertEqual($0 as? BackupError, .unsupportedVersion(4)) }
        XCTAssertEqual(try f.current().payload, original.payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.folder.path))
    }

    func testEmptyMalformedMissingFieldsAndNonBackupRejectWithoutMutation() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let before = try f.current()
        let original = String(decoding: try f.bytes(before), as: UTF8.self)
        let missing = original.replacingOccurrences(of: "\"toWalletId\":null,", with: "")
        for data in [Data(), Data("{".utf8), Data("%PDF-1.4".utf8), Data("{}".utf8), Data(missing.utf8)] {
            XCTAssertThrowsError(try f.restorer().restore(data))
            XCTAssertEqual(try f.current().payload, before.payload)
        }
    }

    func testAllStructuralFailuresRejectEvenWithRecomputedChecksum() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        let cases: [(inout BackupFile) -> Void] = [
            { $0.payload.wallets[1].id = $0.payload.wallets[0].id },
            { $0.payload.categories[1].id = $0.payload.categories[0].id },
            { $0.payload.transactions[1].id = $0.payload.transactions[0].id },
            { $0.payload.transactions[0].walletId = UUID().uuidString },
            { $0.payload.transactions[0].amount = -1 },
            { $0.payload.transactions[0].amount = 0 },
            { $0.payload.wallets[0].kind = "invalid" },
            { $0.payload.categories[0].kind = "transfer" },
            { $0.payload.transactions[0].kind = "invalid" },
            { $0.summary.transactions += 1 },
            { file in let i = file.payload.transactions.firstIndex { $0.kind == "transfer" }!; file.payload.transactions[i].toWalletId = file.payload.transactions[i].walletId },
            { file in let i = file.payload.transactions.firstIndex { $0.kind == "transfer" }!; file.payload.transactions[i].categoryId = file.payload.categories[0].id },
            { file in let i = file.payload.transactions.firstIndex { $0.kind == "expense" }!; file.payload.transactions[i].categoryId = nil },
            { file in let i = file.payload.transactions.firstIndex { $0.kind == "expense" }!; file.payload.transactions[i].categoryId = file.payload.categories.first { $0.kind == "income" }!.id }
        ]
        for mutate in cases {
            var invalid = original; mutate(&invalid); invalid.checksum = try BackupFile.digest(invalid.payload)
            XCTAssertThrowsError(try f.restorer().restore(f.bytes(invalid)))
            XCTAssertEqual(try f.current().payload, original.payload)
        }
    }

    func testInjectedFailureAfterDeletionRollsBackEverything() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        var restorer = f.restorer(); restorer.checkpoint = { _ in throw Injected.failure }
        XCTAssertThrowsError(try restorer.restore(f.bytes(original), now: fixed))
        XCTAssertEqual(try f.current().payload, original.payload)
        XCTAssertEqual(try f.current().summary.expectedBalances, original.summary.expectedBalances)
    }

    func testFailureBeforeSaveAndBalanceMismatchRollBack() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        var restorer = f.restorer()
        restorer.beforeSave = { context in
            let wallet = try XCTUnwrap(context.fetch(FetchDescriptor<Wallet>()).first { !$0.isDeleted })
            wallet.openingBalance = 42
        }
        XCTAssertThrowsError(try restorer.restore(f.bytes(original), now: fixed))
        XCTAssertEqual(try f.current().payload, original.payload)
        var wrong = original
        wrong.summary.expectedBalances[original.payload.wallets[0].id] = 42
        XCTAssertThrowsError(try f.restorer().restore(f.bytes(wrong))) { XCTAssertEqual($0 as? BackupError, .balances) }
        XCTAssertEqual(try f.current().payload, original.payload)
    }

    func testPreRestoreFailureStopsBeforeDataChanges() async throws {
        let f = try Fixture(); defer { f.clean() }; try f.seed()
        let original = try f.current()
        var exporter = f.exporter; exporter.beforeWrite = { throw Injected.failure }
        let restorer = BackupRestorer(container: f.container, exporter: exporter, defaults: f.defaults)
        XCTAssertThrowsError(try restorer.restore(f.bytes(original))) { XCTAssertEqual($0 as? BackupError, .preRestore) }
        XCTAssertEqual(try f.current().payload, original.payload)
    }
}
