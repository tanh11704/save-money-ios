import Foundation
import SwiftData

@MainActor
struct DefaultDataSeeder {
    static let marker = "didSeedDefaults"

    static func installIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: marker) else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard try context.fetch(FetchDescriptor<Wallet>()).allSatisfy({ !$0.isOwn }),
              try context.fetchCount(FetchDescriptor<Category>()) == 0,
              try context.fetchCount(FetchDescriptor<Transaction>()) == 0 else { return }
        context.insert(Wallet(name: "Tiền mặt"))
        // Rent and bills are paid once per cycle, so they start out fixed.
        let expense: [(String, String, Bool)] = [
            ("Ăn uống", "fork.knife", false), ("Đi lại", "bus", false), ("Nhà ở", "house", true), ("Hóa đơn", "doc.text", true),
            ("Mua sắm", "bag", false), ("Sức khỏe", "cross.case", false), ("Giải trí", "gamecontroller", false), ("Khác", "tag", false)
        ]
        for (name, icon, isFixed) in expense {
            let category = Category(name: name, kind: .expense, icon: icon)
            category.isFixed = isFixed
            context.insert(category)
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
