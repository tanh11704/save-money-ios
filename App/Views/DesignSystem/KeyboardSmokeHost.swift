#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Isolated fixtures for UI automation. Never opens the user's store.
@MainActor
struct KeyboardSmokeHost: View {
    let screen: String
    let container: ModelContainer
    @StateObject private var store: TransactionScreenStore
    init(screen: String) {
        self.screen = screen
        UIView.setAnimationsEnabled(false) // UI fixture only; leaves focus and keyboard dismissal real.
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        let wallet = Wallet(name: "Tien mat")
        container.mainContext.insert(wallet)
        let category = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
        container.mainContext.insert(category)
        if screen == "performance" {
            let bank = Wallet(name: "Ngân hàng", openingBalance: 20_000_000, kind: .bank)
            container.mainContext.insert(bank)
            for index in 0..<5_000 {
                container.mainContext.insert(Transaction(amount: Int64(1_000 + index % 100 * 1_000), kind: .expense,
                    date: Date().addingTimeInterval(-Double(index % 90) * 86_400),
                    wallet: index.isMultiple(of: 2) ? wallet : bank, category: category))
            }
        }
        // The screen store reads through a separate ModelContext, so inserted
        // fixtures must be committed before configuring it.
        try! container.mainContext.save()
        let store = TransactionScreenStore()
        store.configure(container: container)
        precondition(store.ready && store.wallets.contains(where: { $0.id == wallet.id }) && !store.categories.isEmpty,
                     "Keyboard smoke fixture failed to load committed wallet/category data")
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        NavigationStack {
            switch screen {
            case "transaction", "performance": TransactionFormView(store: store)
            case "category": CategoryFormView(store: store)
            case "recurring": RecurringFormView(store: store)
            default: WalletFormView(store: store)
            }
        }.modelContainer(container)
    }
}
#endif
