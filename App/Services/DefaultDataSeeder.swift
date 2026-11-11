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
        let expense: [(String, String)] = [
            ("Ăn uống", "fork.knife"), ("Đi lại", "bus"), ("Nhà ở", "house"), ("Hóa đơn", "doc.text"),
            ("Mua sắm", "bag"), ("Sức khỏe", "cross.case"), ("Giải trí", "gamecontroller"), ("Khác", "tag")
        ]
        for (name, icon) in expense { context.insert(Category(name: name, kind: .expense, icon: icon)) }
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
