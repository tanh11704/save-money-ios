import Foundation

@MainActor
struct BackupEncryptionManager {
    let exporter: BackupExporter
    var protection: BackupProtection { exporter.protection }

    func enable(key: BackupCrypto.DerivedKey) throws { try install(key: key, reencrypt: false, oldPassword: nil) }
    func changePassword(oldPassword: String, key: BackupCrypto.DerivedKey, reencrypt: Bool) throws {
        try checkPassword(oldPassword)
        try install(key: key, reencrypt: reencrypt, oldPassword: oldPassword)
    }
    func checkPassword(_ password: String) throws {
        let entries = try BackupCatalog.entries(in: exporter.directory, protection: protection)
        guard let latest = entries.first(where: \.encrypted) else { throw BackupError.unreadable }
        let plain = try BackupCrypto.open(Data(contentsOf: latest.url), password: password)
        _ = try BackupValidator.read(plain)
        protection.defaults.set(Date(), forKey: "SaveMoney.lastBackupPasswordCheck")
    }
    func disable() throws {
        try protection.keyStore.delete()
        protection.defaults.set(false, forKey: "SaveMoney.backupEncryptionEnabled")
    }
    private func install(key: BackupCrypto.DerivedKey, reencrypt: Bool, oldPassword: String?) throws {
        struct Rewrite { let source: URL; let target: URL; let original: Data; let encrypted: Data }
        var rewrites: [Rewrite] = []
        for source in try IntegrityChecker.files(in: exporter.directory) {
            let original = try Data(contentsOf: source)
            if BackupCrypto.isEncrypted(original) && !reencrypt { continue } // Old encrypted files keep their old passwords.
            let plain: Data
            if BackupCrypto.isEncrypted(original) {
                plain = try protection.plaintext(original, password: oldPassword)
            } else { plain = original }
            let file = try BackupValidator.read(plain).file
            let encrypted = try BackupCrypto.seal(plain, with: key, createdAt: BackupFile.date(file.createdAt))
            guard try BackupCrypto.open(encrypted, key: key) == plain else { throw BackupCrypto.CryptoError.wrongPasswordOrTampered }
            let name = source.deletingPathExtension().lastPathComponent
            let target = source.deletingLastPathComponent().appendingPathComponent(name + (name.hasSuffix("-encrypted") ? "" : "-encrypted") + ".savemoney")
            guard target == source || !FileManager.default.fileExists(atPath: target.path) else { throw BackupError.collision }
            rewrites.append(Rewrite(source: source, target: target, original: original, encrypted: encrypted))
        }
        let oldEnabled = protection.enabled, oldKey = try protection.keyStore.read()
        if oldEnabled && oldKey == nil { throw BackupCrypto.CryptoError.keyUnavailable }
        var newBackup: URL?, written: [Rewrite] = []
        do {
            try protection.keyStore.save(key)
            for rewrite in rewrites {
                written.append(rewrite)
                try rewrite.encrypted.write(to: rewrite.target, options: .atomic)
                let readBack = try Data(contentsOf: rewrite.target)
                _ = try BackupValidator.read(BackupCrypto.open(readBack, key: key))
            }
            // Reserve converted names before exporting the current snapshot, so a
            // same-second plaintext backup cannot collide with the new encrypted one.
            newBackup = try exporter.export(kind: .manual, encryptionKey: key)
            for rewrite in rewrites where rewrite.source != rewrite.target { try FileManager.default.removeItem(at: rewrite.source) }
            try BackupCatalog.rotate(directory: exporter.directory)
            // Commit the enabled setting only after every original plaintext
            // file has a verified encrypted replacement. An interrupted first
            // activation must never claim that all old files are protected.
            protection.defaults.set(true, forKey: "SaveMoney.backupEncryptionEnabled")
            protection.defaults.set(Date(), forKey: "SaveMoney.lastBackupPasswordCheck")
        } catch {
            // Keep the original files and original key if activation/rekey fails.
            for rewrite in written {
                try? rewrite.original.write(to: rewrite.source, options: .atomic)
                if rewrite.source != rewrite.target { try? FileManager.default.removeItem(at: rewrite.target) }
            }
            if let newBackup { try? FileManager.default.removeItem(at: newBackup) }
            if let oldKey { try? protection.keyStore.save(oldKey) } else { try? protection.keyStore.delete() }
            protection.defaults.set(oldEnabled, forKey: "SaveMoney.backupEncryptionEnabled")
            throw error
        }
    }
}
