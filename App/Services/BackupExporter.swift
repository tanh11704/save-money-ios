import Foundation
import SwiftData

@MainActor
struct BackupExporter {
    enum Kind: String { case auto = "Auto", manual = "Manual", preRestore = "PreRestore" }
    let container: ModelContainer
    let directory: URL
    var protection = BackupProtection()
    var appVersion = BackupExporter.applicationVersion
    static var applicationVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    var beforeWrite: (() throws -> Void)?
    var afterWrite: ((URL) throws -> Void)?

    func capture(now: Date = Date()) throws -> BackupFile {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let wallets = try context.fetch(FetchDescriptor<Wallet>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let categories = try context.fetch(FetchDescriptor<Category>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let budgets = try context.fetch(FetchDescriptor<Budget>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let recurringRules = try context.fetch(FetchDescriptor<RecurringRule>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let payload = BackupFile.Payload(
            wallets: try wallets.map { .init(id: $0.id.uuidString, name: $0.name, kind: $0.kindRaw,
                openingBalance: $0.openingBalance, isArchived: $0.isArchived, createdAt: try BackupFile.milliseconds($0.createdAt)) },
            categories: categories.map { .init(id: $0.id.uuidString, name: $0.name, kind: $0.kindRaw, icon: $0.icon, isArchived: $0.isArchived) },
            transactions: try transactions.map { .init(id: $0.id.uuidString, amount: $0.amount, kind: $0.kindRaw,
                date: try BackupFile.milliseconds($0.date), note: $0.note, walletId: $0.wallet?.id.uuidString,
                toWalletId: $0.toWallet?.id.uuidString, categoryId: $0.category?.id.uuidString, recurrenceKey: $0.recurrenceKey, includesRecurrenceKey: true) },
            budgets: try budgets.map { .init(id: $0.id.uuidString, scopeRaw: $0.scopeRaw, categoryID: $0.category?.id.uuidString,
                limit: $0.limit, startYear: $0.startYear, startMonth: $0.startMonth, isArchived: $0.isArchived,
                createdAt: try BackupFile.milliseconds($0.createdAt)) },
            recurringRules: try recurringRules.map { .init(id: $0.id.uuidString, name: $0.name, kindRaw: $0.kindRaw, amount: $0.amount,
                note: $0.note, walletId: $0.wallet?.id.uuidString, toWalletId: $0.toWallet?.id.uuidString, categoryId: $0.category?.id.uuidString,
                frequencyRaw: $0.frequencyRaw, interval: $0.interval, startDate: try BackupFile.milliseconds($0.startDate),
                endDate: try $0.endDate.map(BackupFile.milliseconds), generatedThrough: try $0.generatedThrough.map(BackupFile.milliseconds),
                isPaused: $0.isPaused, createdAt: try BackupFile.milliseconds($0.createdAt)) })
        let graph = BackupValidator.Graph(wallets: wallets, categories: categories, transactions: transactions)
        let file = BackupFile(schemaVersion: 3, createdAt: try BackupFile.milliseconds(now), appVersion: appVersion,
            checksum: try BackupFile.digest(payload), summary: .init(wallets: wallets.count, categories: categories.count,
                transactions: transactions.count, budgets: budgets.count, recurringRules: recurringRules.count, expectedBalances: try BackupValidator.expectedBalances(graph)), payload: payload)
        _ = try BackupValidator.validate(file)
        return file
    }

    func export(kind: Kind, now: Date = Date(), captured: BackupFile? = nil, encryptionKey: BackupCrypto.DerivedKey? = nil) throws -> URL {
        let key = try encryptionKey ?? protection.exportKey()
        let file = try captured ?? capture(now: now)
        _ = try BackupValidator.validate(file)
        let folder = kind == .preRestore ? directory.appendingPathComponent("PreRestore", isDirectory: true) : directory
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try beforeWrite?()
        let plain = try BackupFile.encoder().encode(file)
        let bytes = try key.map { try BackupCrypto.seal(plain, with: $0, createdAt: now) } ?? plain
        try bytes.write(to: temporary, options: .withoutOverwriting)
        try afterWrite?(temporary)
        let readBack = try BackupValidator.decode(Data(contentsOf: temporary), protection: protection)
        guard readBack.file == file else { throw BackupError.unreadable }
        let formatter = DateFormatter()
        formatter.calendar = LocalCalendar.calendar; formatter.timeZone = LocalCalendar.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss"
        // Preserve the specified filename format without overwriting a same-second backup.
        for offset in 0..<86_400 {
            let stamp = formatter.string(from: now.addingTimeInterval(TimeInterval(offset)))
            let target = folder.appendingPathComponent("SaveMoney-\(stamp)-\(kind.rawValue)" + (key == nil ? ".json" : "-encrypted.savemoney"))
            if !manager.fileExists(atPath: target.path) {
                try manager.moveItem(at: temporary, to: target)
                return target
            }
        }
        throw BackupError.collision
    }
}
