import SwiftData
import Foundation

// Frozen copies preserve V1 independently of relationships discovered in V2.
enum SaveMoneySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Wallet.self, Category.self, Transaction.self] }

    @Model
    final class Wallet {
        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = "cash"
        var openingBalance: Int64 = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()

        init(name: String, openingBalance: Int64 = 0, kind: WalletKind = .cash) {
            self.name = name
            self.kindRaw = kind.rawValue
            self.openingBalance = openingBalance
        }
    }

    @Model
    final class Category {
        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = TransactionKind.expense.rawValue
        var icon: String = "tag"
        var isArchived: Bool = false

        init(name: String, kind: TransactionKind, icon: String = "tag") {
            self.name = name
            self.kindRaw = kind.rawValue
            self.icon = icon
        }
    }

    @Model
    final class Transaction {
        var id: UUID = UUID()
        var amount: Int64 = 1
        var kindRaw: String = TransactionKind.expense.rawValue
        var date: Date = Date()
        var note: String = ""
        var wallet: Wallet?
        var toWallet: Wallet?
        var category: Category?

        init(amount: Int64, kind: TransactionKind, date: Date = Date(), note: String = "",
             wallet: Wallet, toWallet: Wallet? = nil, category: Category? = nil) {
            self.amount = amount
            self.kindRaw = kind.rawValue
            self.date = date
            self.note = note
            self.wallet = wallet
            self.toWallet = toWallet
            self.category = category
        }
    }
}

enum SaveMoneySchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Wallet.self, Category.self, Transaction.self, Budget.self] }
}

enum SaveMoneyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SaveMoneySchemaV1.self, SaveMoneySchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SaveMoneySchemaV1.self, toVersion: SaveMoneySchemaV2.self)]
    }
}
