#if DEBUG
import SwiftData
import SwiftUI

@MainActor
private struct AccessibilityPreview: View {
    @StateObject private var runtime: AppRuntime
    init() {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let defaults = UserDefaults(suiteName: "SaveMoneyPreview.\(UUID().uuidString)")!
        var exporter = BackupExporter(container: container, directory: FileManager.default.temporaryDirectory.appendingPathComponent("SaveMoneyPreview-\(UUID().uuidString)"))
        exporter.protection = BackupProtection(defaults: defaults)
        let scheduler = BackupScheduler(exporter: exporter, defaults: defaults)
        _runtime = StateObject(wrappedValue: AppRuntime(container: container, scheduler: scheduler, lock: AppLockService(authenticator: DeviceAuthenticator(), defaults: defaults)))
    }
    var body: some View {
        ContentView(settings: runtime.settings, lock: runtime.lock)
            .modelContainer(runtime.container).environmentObject(runtime).environmentObject(runtime.router)
    }
}
#Preview("AX5 — tối") { AccessibilityPreview().environment(\.dynamicTypeSize, .accessibility5).preferredColorScheme(.dark) }
#Preview("Chữ nhỏ nhất — sáng") { AccessibilityPreview().environment(\.dynamicTypeSize, .xSmall).preferredColorScheme(.light) }
#endif
