import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class BackupCryptoTests: XCTestCase {
    // RFC 7914 §11, PBKDF2-HMAC-SHA256, Password/NaCl, 80000 rounds, 64 bytes.
    func testRFC7914KnownAnswer() throws {
        let result = try BackupCrypto.pbkdf2(password: Data("Password".utf8), salt: Data("NaCl".utf8), iterations: 80_000, length: 64)
        XCTAssertEqual(result.map { String(format: "%02x", $0) }.joined(), "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d")
    }
    func testRoundTripRandomNoncesWrongPasswordAndUnicodeNormalization() throws {
        let password = "Mật khẩu rất dài 2026", salt = Data(repeating: 4, count: 16)
        let key = try BackupCrypto.deriveKey(password: password, salt: salt, iterations: 100_000)
        let nfd = try BackupCrypto.deriveKey(password: password.decomposedStringWithCanonicalMapping, salt: salt, iterations: 100_000)
        XCTAssertEqual(key.keyID, nfd.keyID)
        let bytes = Data("nguyên dữ liệu v3".utf8), now = Date()
        let one = try BackupCrypto.seal(bytes, with: key, createdAt: now), two = try BackupCrypto.seal(bytes, with: key, createdAt: now)
        XCTAssertNotEqual(one, two); XCTAssertTrue(BackupCrypto.isEncrypted(one))
        XCTAssertEqual(try BackupCrypto.open(one, password: password), bytes)
        XCTAssertThrowsError(try BackupCrypto.open(one, password: "wrong password")) { XCTAssertEqual($0 as? BackupCrypto.CryptoError, .wrongPasswordOrTampered) }
    }
    func testHeaderAndCiphertextTamperingAndKDFBounds() throws {
        let key = try BackupCrypto.deriveKey(password: "long enough password", iterations: 100_000)
        let bytes = try BackupCrypto.seal(Data([1, 2, 3]), with: key, createdAt: Date())
        let original = try BackupCrypto.envelope(bytes)
        for edit in 0...3 {
            var changed = original
            switch edit {
            case 0: changed.sealed[12] ^= 1
            case 1: changed.header.kdf.salt[0] ^= 1
            case 2: changed.header.kdf.iterations += 1
            default: changed.header.createdAt += 1
            }
            XCTAssertThrowsError(try BackupCrypto.open(BackupFile.encoder().encode(changed), key: key))
        }
        for iterations in [99_999, 10_000_001, Int.max] {
            var changed = original; changed.header.kdf.iterations = iterations
            XCTAssertThrowsError(try BackupCrypto.open(BackupFile.encoder().encode(changed), password: "long enough password")) {
                XCTAssertEqual($0 as? BackupCrypto.CryptoError, .invalidEnvelope)
            }
        }
    }
}
