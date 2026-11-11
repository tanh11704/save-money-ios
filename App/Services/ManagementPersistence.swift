import Foundation
import SwiftData

/// Each operation saves once, and rollback never touches another screen's draft.
@MainActor
struct ManagementPersistence {
    let container: ModelContainer
    var origin: UUID? = nil

    func write<T>(_ body: (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try body(context)
            try context.save()
            NotificationCenter.default.post(name: .ledgerDidChange, object: container, userInfo: ["origin": origin?.uuidString ?? ""])
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
