import CryptoKit
import Foundation
import Security

protocol BackupKeyStoring {
    func read() throws -> BackupCrypto.DerivedKey?
    func save(_ key: BackupCrypto.DerivedKey) throws
    func delete() throws
}

struct BackupKeyStore: BackupKeyStoring {
    private struct Record: Codable { let key: Data; let salt: Data; let iterations: Int; let keyID: String }
    var service = "vn.tanh11704.SaveMoney.backupEncryption"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current-key", kSecAttrSynchronizable as String: false] }
    func read() throws -> BackupCrypto.DerivedKey? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let record = try? JSONDecoder().decode(Record.self, from: data),
              record.key.count == 32, record.salt.count == 16, (100_000...10_000_000).contains(record.iterations) else { throw BackupCrypto.CryptoError.keyUnavailable }
        let key = BackupCrypto.DerivedKey(key: SymmetricKey(data: record.key), salt: record.salt, iterations: record.iterations)
        guard key.keyID == record.keyID else { throw BackupCrypto.CryptoError.keyUnavailable }
        return key
    }
    func save(_ key: BackupCrypto.DerivedKey) throws {
        let record = Record(key: key.key.withUnsafeBytes { Data($0) }, salt: key.salt, iterations: key.iterations, keyID: key.keyID)
        let data = try JSONEncoder().encode(record)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw BackupCrypto.CryptoError.keyUnavailable }
        } else if status != errSecSuccess { throw BackupCrypto.CryptoError.keyUnavailable }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BackupCrypto.CryptoError.keyUnavailable }
    }
}

// No password is stored. Enabled is independent of Keychain availability so a
// lost/locked key can never silently switch an export to plaintext.
struct BackupProtection {
    let defaults: UserDefaults
    let keyStore: any BackupKeyStoring
    init(defaults: UserDefaults = .standard, keyStore: any BackupKeyStoring = BackupKeyStore()) { self.defaults = defaults; self.keyStore = keyStore }
    var enabled: Bool { defaults.bool(forKey: "SaveMoney.backupEncryptionEnabled") }
    func exportKey() throws -> BackupCrypto.DerivedKey? {
        guard enabled else { return nil }
        guard let key = try keyStore.read() else { throw BackupCrypto.CryptoError.keyUnavailable }
        return key
    }
    func plaintext(_ data: Data, password: String? = nil) throws -> Data {
        guard BackupCrypto.isEncrypted(data) else { return data }
        let envelope = try BackupCrypto.envelope(data)
        if let password { return try BackupCrypto.open(data, password: password) }
        guard let key = try keyStore.read(), key.keyID == envelope.header.keyID else { throw BackupCrypto.CryptoError.keyUnavailable }
        return try BackupCrypto.open(data, key: key)
    }
}
