import SwiftData
import SwiftUI

@main
struct SaveMoneyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Wallet.self, Category.self, Transaction.self])
    }
}

