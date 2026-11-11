import Foundation
import SwiftData

@MainActor
struct BackupRestorer {
    let container: ModelContainer
    let exporter: BackupExporter
    var defaults: UserDefaults = .standard
    var checkpoint: ((ModelContext) throws -> Void)?
    var beforeSave: ((ModelContext) throws -> Void)?

    func restore(_ data: Data, now: Date = Date()) throws -> BackupValidator.Validated {
        // Revalidate the exact bytes after the user's confirmation, before any writes.
        let validated = try BackupValidator.read(data)
        do {
            let url = try exporter.export(kind: .preRestore, now: now)
            _ = try BackupValidator.read(Data(contentsOf: url))
            try BackupCatalog.rotate(directory: exporter.directory)
        } catch { throw BackupError.preRestore }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for record in try context.fetch(FetchDescriptor<Budget>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Wallet>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Category>()) { context.delete(record) }
            try checkpoint?(context)
            let graph = try BackupValidator.graph(validated.file.payload)
            graph.wallets.forEach { context.insert($0) }
            graph.categories.forEach { context.insert($0) }
            graph.budgets.forEach { context.insert($0) }
            graph.transactions.forEach { context.insert($0) }
            try beforeSave?(context)
            guard try BackupValidator.expectedBalances(graph) == validated.file.summary.expectedBalances else { throw BackupError.balances }
            try context.save()
        } catch { context.rollback(); throw error }
        RecentSelectionStore(defaults: defaults).clear()
        defaults.set(true, forKey: DefaultDataSeeder.marker)
        NotificationCenter.default.post(name: .ledgerDidRestore, object: container)
        return validated
    }
}
