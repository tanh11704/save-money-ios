import SwiftData
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @ObservedObject var settings: BackupScreenStore
    @ObservedObject var lock: AppLockService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TransactionScreenStore()
    @State private var showingRecurring = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if store.ready {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        TransactionFormView(store: store)
                            .navigationTitle("Thêm giao dịch")
                    }
                    .tabItem { Label("Thêm", systemImage: "plus.circle") }
                    .tag(0)
                    NavigationStack {
                        TransactionHistoryView(store: store)
                    }
                    .tabItem { Label("Lịch sử", systemImage: "list.bullet") }
                    .tag(1)
                    NavigationStack {
                        WalletListView(store: store)
                    }
                    .tabItem { Label("Ví", systemImage: "wallet.bifold") }
                    .tag(2)
                    NavigationStack {
                        StatsView(store: store)
                    }
                    .tabItem { Label("Thống kê", systemImage: "list.number") }
                    .tag(3)
                    NavigationStack { SettingsView(store: settings, lock: lock) }
                        .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                        .badge(settings.health.level == .critical ? "!" : nil).tag(4)
                }
            } else {
                VStack(spacing: 16) {
                    if let message = store.errorMessage {
                        Text(message)
                        Button("Thử lại") { store.retry() }
                            .frame(minHeight: 44)
                    } else {
                        ProgressView("Đang mở dữ liệu…")
                    }
                }
                .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidChange)) { _ in
            guard store.ready else { return }
            do { try store.reload() } catch { store.errorMessage = "Chưa tải lại được dữ liệu. Hãy tải lại." }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidRestore)) { _ in
            selectedTab = 0
            do { try store.reload() } catch { store.errorMessage = "Đã khôi phục, nhưng chưa tải lại được dữ liệu. Hãy mở lại app." }
        }
        .overlay(alignment: .top) {
            if let message = runtime.recurringMessage {
                Button { showingRecurring = true } label: {
                    Text(message).font(.footnote).padding().frame(maxWidth: .infinity, minHeight: 44).background(.regularMaterial)
                }
            } else if let error = settings.scheduler.lastError {
                Text(error).font(.footnote).padding().frame(maxWidth: .infinity)
                    .background(.regularMaterial).accessibilityAddTraits(.isStaticText)
            }
        }
        .sheet(isPresented: $showingRecurring) {
            NavigationStack { RecurringListView(store: store) }
        }
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .environment(\.calendar, LocalCalendar.calendar)
        .environment(\.timeZone, LocalCalendar.calendar.timeZone)
        .task { store.configure(container: modelContext.container) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.ready else { return }
            do { try store.reload() }
            catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
        }
    }
}
