import CommonCrypto
import CryptoKit
import Foundation
import Security

struct BackupCrypto {
    enum CryptoError: LocalizedError, Equatable {
        case invalidPassword, invalidEnvelope, wrongPasswordOrTampered, keyUnavailable, derivationFailed
        var errorDescription: String? {
            switch self {
            case .invalidPassword: return "Mật khẩu phải có ít nhất 10 ký tự."
            case .invalidEnvelope: return "Phong bì mã hóa không hợp lệ hoặc chưa được hỗ trợ."
            case .wrongPasswordOrTampered: return "Sai mật khẩu hoặc file đã bị sửa. Dữ liệu hiện tại giữ nguyên."
            case .keyUnavailable: return "Không đọc được khóa Keychain. Đã bỏ qua sao lưu; không ghi bản không mã hóa."
            case .derivationFailed: return "Không tạo được khóa mã hóa."
            }
        }
    }
    struct DerivedKey {
        let key: SymmetricKey
        let salt: Data
        let iterations: Int
        var keyID: String { key.withUnsafeBytes { SHA256.hash(data: Data($0)).prefix(8).map { String(format: "%02x", $0) }.joined() } }
    }
    struct KDF: Codable, Equatable { var name: String; var iterations: Int; var salt: Data }
    struct Header: Codable, Equatable {
        var format = "savemoney-backup-encrypted"
        var envelopeVersion = 1
        var kdf: KDF
        var cipher = "AES-GCM-256"
        var keyID: String
        var createdAt: Int64
    }
    struct Envelope: Codable {
        var header: Header
        var sealed: Data
        enum CodingKeys: String, CodingKey { case sealed }
        init(header: Header, sealed: Data) { self.header = header; self.sealed = sealed }
        init(from decoder: Decoder) throws {
            header = try Header(from: decoder)
            sealed = try decoder.container(keyedBy: CodingKeys.self).decode(Data.self, forKey: .sealed)
        }
        func encode(to encoder: Encoder) throws {
            try header.encode(to: encoder)
            var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(sealed, forKey: .sealed)
        }
    }
    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CryptoError.derivationFailed }
        return Data(bytes)
    }
    static func deriveKey(password: String, salt: Data? = nil, iterations: Int = 600_000) throws -> DerivedKey {
        let password = password.precomposedStringWithCanonicalMapping
        guard password.count >= 10 else { throw CryptoError.invalidPassword }
        let salt = try salt ?? randomSalt()
        guard salt.count == 16, (100_000...10_000_000).contains(iterations) else { throw CryptoError.invalidEnvelope }
        return DerivedKey(key: SymmetricKey(data: try pbkdf2(password: Data(password.utf8), salt: salt, iterations: iterations, length: 32)), salt: salt, iterations: iterations)
    }
    // Internal primitive also accepts RFC test-vector salt/round counts. Untrusted
    // envelopes always pass through validatedHeader before this is called.
    static func pbkdf2(password: Data, salt: Data, iterations: Int, length: Int) throws -> Data {
        guard (1...10_000_000).contains(iterations), (1...64).contains(length) else { throw CryptoError.invalidEnvelope }
        var output = Data(count: length)
        let result = output.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pass in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations), out.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
                }
            }
        }
        guard result == kCCSuccess else { throw CryptoError.derivationFailed }
        return output
    }
    static func envelope(_ data: Data) throws -> Envelope {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw CryptoError.invalidEnvelope }
        let h = envelope.header
        guard h.format == "savemoney-backup-encrypted", h.envelopeVersion == 1, h.cipher == "AES-GCM-256",
              h.kdf.name == "PBKDF2-HMAC-SHA256", (100_000...10_000_000).contains(h.kdf.iterations), h.kdf.salt.count == 16,
              h.keyID.count == 16, h.keyID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), envelope.sealed.count >= 28 else { throw CryptoError.invalidEnvelope }
        _ = try BackupFile.date(h.createdAt)
        return envelope
    }
    static func seal(_ plaintext: Data, with key: DerivedKey, createdAt: Date) throws -> Data {
        let header = Header(kdf: KDF(name: "PBKDF2-HMAC-SHA256", iterations: key.iterations, salt: key.salt), keyID: key.keyID, createdAt: try BackupFile.milliseconds(createdAt))
        let box = try AES.GCM.seal(plaintext, using: key.key, authenticating: BackupFile.encoder().encode(header))
        guard let combined = box.combined else { throw CryptoError.derivationFailed }
        return try BackupFile.encoder().encode(Envelope(header: header, sealed: combined))
    }
    static func open(_ data: Data, key: DerivedKey) throws -> Data {
        let e = try envelope(data)
        guard key.keyID == e.header.keyID, key.salt == e.header.kdf.salt, key.iterations == e.header.kdf.iterations else { throw CryptoError.wrongPasswordOrTampered }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: e.sealed), using: key.key, authenticating: BackupFile.encoder().encode(e.header)) }
        catch { throw CryptoError.wrongPasswordOrTampered }
    }
    static func open(_ data: Data, password: String) throws -> Data {
        let e = try envelope(data) // Validate KDF limits before doing any expensive work.
        do {
            let key = try deriveKey(password: password, salt: e.header.kdf.salt, iterations: e.header.kdf.iterations)
            return try open(data, key: key)
        } catch CryptoError.invalidPassword { throw CryptoError.wrongPasswordOrTampered }
    }
    static func isEncrypted(_ data: Data) -> Bool {
        struct Format: Decodable { let format: String }
        return (try? JSONDecoder().decode(Format.self, from: data).format) == "savemoney-backup-encrypted"
    }
}
