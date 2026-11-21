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

    @Model
    final class Budget {
        var id: UUID = UUID()
        var scopeRaw: String = "category"
        var category: Category? = nil
        var limit: Int64 = 0
        var startYear: Int = 0
        var startMonth: Int = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()

        init() {}

        var rule: BudgetRule? {
            guard (1...MoneyFormatter.maximumInput).contains(limit),
                  let month = try? ReportingMonth(year: startYear, month: startMonth) else { return nil }
            let scope: BudgetRule.Scope
            switch scopeRaw {
            case "total":
                guard category == nil else { return nil }
                scope = .total
            case "category":
                guard let category, category.kindRaw == TransactionKind.expense.rawValue else { return nil }
                scope = .category(category.id)
            default: return nil
            }
            return BudgetRule(id: id, scope: scope, limit: limit, startMonth: month, isArchived: isArchived)
        }
    }
}

// Frozen copy of the V3 store (recurring rules), before categories could be marked fixed.
enum SaveMoneySchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Wallet.self, Category.self, Transaction.self, Budget.self, RecurringRule.self] }

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
        var recurrenceKey: String? = nil
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

    @Model
    final class Budget {
        var id: UUID = UUID()
        var scopeRaw: String = "category"
        var category: Category? = nil
        var limit: Int64 = 0
        var startYear: Int = 0
        var startMonth: Int = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()

        init() {}
    }

    @Model
    final class RecurringRule {
        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = TransactionKind.expense.rawValue
        var amount: Int64 = 1
        var note: String = ""
        var wallet: Wallet? = nil
        var toWallet: Wallet? = nil
        var category: Category? = nil
        var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
        var interval: Int = 1
        var startDate: Date = Date()
        var endDate: Date? = nil
        var generatedThrough: Date? = nil
        var isPaused: Bool = false
        var createdAt: Date = Date()
        init() {}
    }
}

/// Current schema: categories can be marked fixed (`Category.isFixed`).
enum SaveMoneySchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [Wallet.self, Category.self, Transaction.self, Budget.self, RecurringRule.self] }
}

enum SaveMoneyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SaveMoneySchemaV1.self, SaveMoneySchemaV2.self, SaveMoneySchemaV3.self, SaveMoneySchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SaveMoneySchemaV1.self, toVersion: SaveMoneySchemaV2.self),
         .lightweight(fromVersion: SaveMoneySchemaV2.self, toVersion: SaveMoneySchemaV3.self),
         markDefaultFixedCategories]
    }

    /// Names of the seeded categories that are paid once per cycle; new installs get them fixed from the seeder.
    static let defaultFixedCategoryNames = ["Nhà ở", "Hóa đơn"]

    /// V3 → V4 adds `Category.isFixed`. Existing users get the seeded rent and bills categories marked fixed,
    /// so the daily plan stops spreading them over the days without any setup.
    static let markDefaultFixedCategories = MigrationStage.custom(
        fromVersion: SaveMoneySchemaV3.self, toVersion: SaveMoneySchemaV4.self, willMigrate: nil,
        didMigrate: { context in
            let categories = try context.fetch(FetchDescriptor<Category>())
            for category in categories where category.kindRaw == TransactionKind.expense.rawValue
                && defaultFixedCategoryNames.contains(where: { ManagementValidation.matches($0, category.name) }) {
                category.isFixed = true
            }
            if context.hasChanges { try context.save() }
        })
}
