import SwiftData

// V1 deliberately retains the original three models unchanged. Future changes
// to their stored properties must first freeze these model definitions.
enum SaveMoneySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Wallet.self, Category.self, Transaction.self] }
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
