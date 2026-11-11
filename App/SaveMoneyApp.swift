import SwiftData
import SwiftUI

@main
@MainActor
struct SaveMoneyApp: App {
    private let container: ModelContainer?

    init() {
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
            let configuration = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("default.store"), cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, migrationPlan: SaveMoneyMigrationPlan.self, configurations: [configuration])
        } catch {
            container = nil // Never delete or silently replace a store that failed to open.
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                AppShell(container: container).modelContainer(container)
            } else {
                Text("Không mở được dữ liệu SaveMoney. Không xóa app; hãy giữ dữ liệu và kiểm tra bản sao lưu trước.")
                    .padding()
            }
        }
    }
}
