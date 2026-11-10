import Foundation
import SwiftData

/// Each operation saves once, and rollback never touches another screen's draft.
@MainActor
struct ManagementPersistence {
    let container: ModelContainer

    func write<T>(_ body: (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try body(context)
            try context.save()
            NotificationCenter.default.post(name: .ledgerDidChange, object: container)
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
