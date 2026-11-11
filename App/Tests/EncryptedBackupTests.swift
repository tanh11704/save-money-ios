import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
@MainActor
final class EncryptedBackupTests: XCTestCase {
    func testEncryptedRoundTripPasswordRestoreAndMissingKeyFailsClosed() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "Encrypted.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let keys = MemoryBackupKeys(), password = "remember this password"
        try keys.save(BackupCrypto.deriveKey(password: password, iterations: 100_000))
        defaults.set(true, forKey: "SaveMoney.backupEncryptionEnabled")
        let protection = BackupProtection(defaults: defaults, keyStore: keys)
        let wallet = Wallet(name: "A", openingBalance: 123); container.mainContext.insert(wallet); try container.mainContext.save()
        var exporter = BackupExporter(container: container, directory: folder); exporter.protection = protection
        let now = Date(), original = try exporter.capture(now: now), url = try exporter.export(kind: .manual, now: now)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-encrypted.savemoney")); XCTAssertTrue(BackupCrypto.isEncrypted(data))
        XCTAssertEqual(try BackupValidator.decode(data, protection: protection).file, original)
        let key = try XCTUnwrap(keys.read()); try keys.delete()
        let files = try IntegrityChecker.checkFiles(in: folder, protection: protection)
        XCTAssertEqual(files.issues.first?.severity, .warning)
        XCTAssertEqual(try BackupCatalog.entries(in: folder, protection: protection).count, 1)
        let scheduler = BackupScheduler(exporter: exporter, defaults: defaults)
        XCTAssertNil(scheduler.automatic()); XCTAssertNotNil(scheduler.lastError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        XCTAssertThrowsError(try BackupRestorer(container: container, exporter: exporter, defaults: defaults).restore(data, password: "incorrect password"))
        XCTAssertEqual(try exporter.capture(now: now), original)
        // Disable only the current export setting to simulate a fresh installation.
        defaults.set(false, forKey: "SaveMoney.backupEncryptionEnabled")
        _ = try BackupRestorer(container: container, exporter: exporter, defaults: defaults).restore(data, password: password)
        XCTAssertEqual(try exporter.capture(now: now), original)
        try keys.save(key); defaults.set(true, forKey: "SaveMoney.backupEncryptionEnabled")
        exporter.afterWrite = { try Data("damaged".utf8).write(to: $0) }
        XCTAssertThrowsError(try exporter.export(kind: .manual))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix("tmp") })
    }
    func testMixedCatalogRotationRetainsTenEvenWhenKeysAreMissing() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "Mixed.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let keys = MemoryBackupKeys(); try keys.save(BackupCrypto.deriveKey(password: "remember this password", iterations: 100_000))
        var exporter = BackupExporter(container: container, directory: folder); exporter.protection = BackupProtection(defaults: defaults, keyStore: keys)
        for day in 0..<12 {
            defaults.set(day % 2 == 0, forKey: "SaveMoney.backupEncryptionEnabled")
            _ = try exporter.export(kind: .manual, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400))
        }
        try keys.delete(); try BackupCatalog.rotate(directory: folder)
        XCTAssertEqual(try BackupCatalog.entries(in: folder, protection: exporter.protection).count, 10)
    }
}
