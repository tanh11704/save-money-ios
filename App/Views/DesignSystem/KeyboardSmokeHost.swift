#if DEBUG
import SwiftUI
import SwiftData

/// Isolated fixtures for UI automation. Never opens the user's store.
@MainActor
struct KeyboardSmokeHost: View {
    let screen: String
    let container: ModelContainer
    @StateObject private var store: TransactionScreenStore
    init(screen: String) {
        self.screen = screen
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        let wallet = Wallet(name: "Tien mat")
        container.mainContext.insert(wallet)
        let store = TransactionScreenStore()
        store.configure(container: container)
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        NavigationStack {
            switch screen {
            case "category": CategoryFormView(store: store)
            case "recurring": RecurringFormView(store: store)
            default: WalletFormView(store: store)
            }
        }.modelContainer(container)
    }
}
#endif
