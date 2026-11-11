import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class MemoryBackupKeys: BackupKeyStoring {
    var key: BackupCrypto.DerivedKey?
    var fails = false
    func read() throws -> BackupCrypto.DerivedKey? { if fails { throw BackupCrypto.CryptoError.keyUnavailable }; return key }
    func save(_ key: BackupCrypto.DerivedKey) throws { if fails { throw BackupCrypto.CryptoError.keyUnavailable }; self.key = key }
    func delete() throws { if fails { throw BackupCrypto.CryptoError.keyUnavailable }; key = nil }
}
final class BackupKeyStoreTests: XCTestCase {
    func testSaveReadOverwriteDeleteAndEnabledFailsClosed() throws {
        let store = MemoryBackupKeys(), suite = "Keys.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try BackupCrypto.deriveKey(password: "first long password", iterations: 100_000)
        let second = try BackupCrypto.deriveKey(password: "second long password", iterations: 100_000)
        try store.save(first); XCTAssertEqual(try store.read()?.keyID, first.keyID)
        try store.save(second); XCTAssertEqual(try store.read()?.keyID, second.keyID)
        try store.delete(); XCTAssertNil(try store.read())
        let protection = BackupProtection(defaults: defaults, keyStore: store)
        XCTAssertNil(try protection.exportKey())
        defaults.set(true, forKey: "SaveMoney.backupEncryptionEnabled")
        XCTAssertThrowsError(try protection.exportKey())
        store.fails = true; XCTAssertThrowsError(try protection.exportKey())
    }
}
