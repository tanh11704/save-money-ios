import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
@MainActor
final class BackupEncryptionManagerTests: XCTestCase {
    func testEnableConvertsPlainFilesIncludingPreRestoreAndChangesPassword() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "EncryptionManager.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let keys = MemoryBackupKeys(); var exporter = BackupExporter(container: container, directory: folder)
        exporter.protection = BackupProtection(defaults: defaults, keyStore: keys)
        _ = try exporter.export(kind: .manual); _ = try exporter.export(kind: .preRestore)
        container.mainContext.insert(Wallet(name: "Dữ liệu mới hơn bản cũ")); try container.mainContext.save()
        let manager = BackupEncryptionManager(exporter: exporter), first = "remember first password", second = "remember second password"
        try manager.enable(key: BackupCrypto.deriveKey(password: first, iterations: 100_000))
        let files = try IntegrityChecker.files(in: folder)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(try BackupCatalog.entries(in: folder, protection: exporter.protection).first?.file?.payload.wallets.first?.name, "Dữ liệu mới hơn bản cũ")
        for file in files { XCTAssertTrue(BackupCrypto.isEncrypted(try Data(contentsOf: file))) }
        try manager.checkPassword(first)
        try manager.changePassword(oldPassword: first, key: BackupCrypto.deriveKey(password: second, iterations: 100_000), reencrypt: true)
        for file in try IntegrityChecker.files(in: folder) { _ = try BackupValidator.decode(Data(contentsOf: file), protection: exporter.protection, password: second) }
        try manager.disable(); XCTAssertNil(try keys.read()); XCTAssertFalse(exporter.protection.enabled)
        for file in try IntegrityChecker.files(in: folder) { _ = try BackupValidator.decode(Data(contentsOf: file), protection: exporter.protection, password: second) }
    }
    func testFailedActivationKeepsPlainOriginalAndDisabledState() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "EncryptionFail.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let keys = MemoryBackupKeys(); var exporter = BackupExporter(container: container, directory: folder)
        exporter.protection = BackupProtection(defaults: defaults, keyStore: keys)
        let url = try exporter.export(kind: .manual), original = try Data(contentsOf: url)
        exporter.afterWrite = { _ in throw BackupError.unreadable }
        XCTAssertThrowsError(try BackupEncryptionManager(exporter: exporter).enable(key: BackupCrypto.deriveKey(password: "remember password", iterations: 100_000)))
        XCTAssertFalse(exporter.protection.enabled); XCTAssertNil(try keys.read()); XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
