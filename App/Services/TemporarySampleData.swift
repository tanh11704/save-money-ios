import Foundation
import SwiftData

/// TEMPORARY, step 2 only. Remove this bootstrap in step 3.
/// Never adds sample records to an existing ledger; never creates transactions.
@MainActor
struct TemporarySampleData {
    static let marker = "SaveMoney.temporaryStep2DataInstalled"

    static func installIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: marker) else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard try context.fetchCount(FetchDescriptor<Wallet>()) == 0,
              try context.fetchCount(FetchDescriptor<Category>()) == 0,
              try context.fetchCount(FetchDescriptor<Transaction>()) == 0 else {
            defaults.set(true, forKey: marker)
            return
        }
        context.insert(Wallet(name: "Tiền mặt"))
        context.insert(Wallet(name: "Ngân hàng"))
        for (name, icon) in [("Ăn uống", "fork.knife"), ("Đi lại", "bus"), ("Khác", "tag")] {
            context.insert(Category(name: name, kind: .expense, icon: icon))
        }
        context.insert(Category(name: "Lương", kind: .income, icon: "banknote"))
        context.insert(Category(name: "Thu nhập khác", kind: .income, icon: "plus.circle"))
        do {
            try context.save()
            defaults.set(true, forKey: marker)
        } catch {
            context.rollback()
            throw error
        }
    }
}
