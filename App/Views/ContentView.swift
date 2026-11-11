import SwiftData
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var runtime: AppRuntime
    @ObservedObject var settings: BackupScreenStore
    @ObservedObject var lock: AppLockService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TransactionScreenStore()
    @State private var showingRecurring = false
    @State private var showingTransfer = false
    @State private var transferSourceID: UUID?
    @State private var dismissedBanner: String?
    @State private var selectedTab = 0
    @State private var navigationGeneration = UUID()

    var body: some View {
        Group {
            if store.ready {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        TransactionFormView(store: store, onNeedsWallet: { selectedTab = 2 })
                    }
                    .tabItem { Label("Thêm", systemImage: "plus.circle.fill") }
                    .tag(0)
                    NavigationStack {
                        TransactionHistoryView(store: store, onAdd: { selectedTab = 0 })
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
                    .tabItem { Label("Thống kê", systemImage: "chart.bar.xaxis") }
                    .tag(3)
                    NavigationStack { SettingsView(store: settings, lock: lock) }
                        .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                        .badge(settings.health.level == .critical ? "!" : nil).tag(4)
                }.id(navigationGeneration)
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
        .onChange(of: router.pending?.id, initial: true) { _, _ in consumeRoute() }
        .onChange(of: store.ready) { _, _ in consumeRoute() }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidChange)) { notification in
            store.receiveLedgerChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidRestore)) { _ in
            selectedTab = 0
            navigationGeneration = UUID()
            store.clearUndo()
            do { try store.reload() } catch { store.errorMessage = "Đã khôi phục, nhưng chưa tải lại được dữ liệu. Hãy mở lại app." }
        }
        .overlay(alignment: .top) {
            if let action = store.undoAction {
                HStack {
                    Text(action.message)
                        .font(.subheadline).lineLimit(2).minimumScaleFactor(0.8)
                    Button("Hoàn tác") { store.undo() }.frame(minHeight: 44)
                    Button("Đóng", systemImage: "xmark") { store.expireUndo(action.id) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.padding(.horizontal).background(.regularMaterial, in: Capsule()).padding()
                    .task(id: action.id) {
                        try? await Task.sleep(for: .seconds(max(0, action.expiresAt.timeIntervalSinceNow)))
                        guard !Task.isCancelled else { return }
                        store.expireUndo(action.id)
                    }
            } else if let count = settings.restoredTransactionCount {
                RestoreSuccessView(transactionCount: count) { settings.restoredTransactionCount = nil }.padding(Spacing.s)
            } else if let message = runtime.recurringMessage, dismissedBanner != message {
                VStack {
                    Callout(level: .info, title: "Giao dịch định kỳ", message: message, actionTitle: "Xem") { showingRecurring = true }
                    Button("Đóng", systemImage: "xmark") { dismissedBanner = message }.frame(minHeight: 44)
                }.padding(8).background(.regularMaterial)
            } else if let error = settings.scheduler.lastError, dismissedBanner != error {
                VStack {
                    Callout(level: .danger, title: "Sao lưu cần kiểm tra", message: error, actionTitle: "Xem") { selectedTab = 4 }
                    Button("Đóng", systemImage: "xmark") { dismissedBanner = error }.frame(minHeight: 44)
                }.padding(8).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingTransfer) { NavigationStack { TransferSheet(store: store, source: store.wallets.first { $0.id == transferSourceID && !$0.isArchived && $0.isOwn }) } }
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
    private func consumeRoute() {
        guard store.ready, let route = router.take(unlocked: lock.state == .unlocked) else { return }
        switch route {
        case .transfer(let from): selectedTab = 2; transferSourceID = from; showingTransfer = true
        case .history: selectedTab = 1
        case .stats: selectedTab = 3
        case .add(let kind, let amount): selectedTab = 0; store.addPrefill = .init(kind: kind, amount: amount)
        }
    }

}
