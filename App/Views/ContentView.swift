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
    @AppStorage(MonthCycle.startDayKey) private var monthStartDay = 1
    @AppStorage(SharedContainer.showsAmountsKey) private var widgetShowsAmounts = false
    @AppStorage(AppearanceSettings.accentKey) private var accentRaw = AppearanceSettings.Accent.standard.rawValue
    @AppStorage(AppearanceSettings.startScreenKey) private var startScreenRaw = AppearanceSettings.StartScreen.overview.rawValue
    @AppStorage(AppearanceSettings.dailyReminderKey) private var dailyReminder = false
    @State private var showingSettings = false
    @State private var appliedStartScreen = false

    /// Tab order: Tổng quan · Lịch sử · Thêm (centre) · Thống kê · Ví. Settings live behind the gear on Tổng quan.
    private enum Tab { static let overview = 0, history = 1, add = 2, stats = 3, wallets = 4 }
    private var accent: Color? { (AppearanceSettings.Accent(rawValue: accentRaw) ?? .standard).color }

    var body: some View {
        Group {
            if store.ready {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        OverviewView(store: store, settings: settings, lock: lock, showingSettings: $showingSettings,
                                     onAdd: { kind in store.addPrefill = .init(kind: kind, amount: nil, clearsSelection: false); selectedTab = Tab.add },
                                     onShowHistory: { selectedTab = Tab.history }, onShowStats: { selectedTab = Tab.stats })
                    }
                    .tabItem { Label("Tổng quan", systemImage: "house.fill") }
                    .badge(settings.health.level == .critical ? "!" : nil)
                    .tag(Tab.overview)
                    NavigationStack {
                        TransactionHistoryView(store: store, onAdd: { selectedTab = Tab.add })
                    }
                    .tabItem { Label("Lịch sử", systemImage: "list.bullet") }
                    .tag(Tab.history)
                    NavigationStack {
                        TransactionFormView(store: store, onNeedsWallet: { selectedTab = Tab.wallets })
                    }
                    .tabItem { Label("Thêm", systemImage: "plus.circle.fill") }
                    .tag(Tab.add)
                    NavigationStack {
                        StatsView(store: store)
                    }
                    .tabItem { Label("Thống kê", systemImage: "chart.bar.xaxis") }
                    .tag(Tab.stats)
                    NavigationStack {
                        WalletListView(store: store)
                    }
                    .tabItem { Label("Ví", systemImage: "wallet.bifold") }
                    .tag(Tab.wallets)
                }
                .id(navigationGeneration)
                .tint(accent)
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
        .onChange(of: store.ready) { _, ready in
            if ready && !appliedStartScreen {
                appliedStartScreen = true
                selectedTab = startScreenRaw == AppearanceSettings.StartScreen.add.rawValue ? Tab.add : Tab.overview
            }
            consumeRoute()
            if ready { store.checkCycleSummary() }
        }
        .onChange(of: dailyReminder) { _, _ in store.scheduleDailyReminder() }
        .onChange(of: widgetShowsAmounts) { _, _ in store.publishWidgetSnapshot() }
        .sheet(item: Binding(get: { store.pendingCycleSummary }, set: { if $0 == nil { store.dismissCycleSummary() } })) { month in
            NavigationStack { CycleSummaryView(store: store, month: month) { store.dismissCycleSummary() } }
        }
        // Month cycles moved: rebuild month reports, budget progress and the month list.
        .onChange(of: monthStartDay) { _, _ in
            guard store.ready else { return }
            do { try store.reload() } catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidChange)) { notification in
            store.receiveLedgerChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerDidRestore)) { _ in
            selectedTab = Tab.overview
            navigationGeneration = UUID()
            store.clearUndo()
            do { try store.reload() } catch { store.errorMessage = "Đã khôi phục, nhưng chưa tải lại được dữ liệu. Hãy mở lại app." }
        }
        .overlay(alignment: .top) {
            if let action = store.undoAction {
                HStack {
                    if !action.restore {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color("Income"))
                            .symbolEffect(.pulse, options: .repeat(2))
                            .accessibilityHidden(true)
                    }
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
                    Callout(level: .danger, title: "Sao lưu cần kiểm tra", message: error, actionTitle: "Xem") { selectedTab = Tab.overview; showingSettings = true }
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
            store.checkCycleSummary()
        }
    }
    private func consumeRoute() {
        guard store.ready, let route = router.take(unlocked: lock.state == .unlocked) else { return }
        switch route {
        case .transfer(let from): selectedTab = Tab.wallets; transferSourceID = from; showingTransfer = true
        case .history: selectedTab = Tab.history
        case .stats: selectedTab = Tab.stats
        case .add(let kind, let amount): selectedTab = Tab.add; store.addPrefill = .init(kind: kind, amount: amount)
        }
    }

}
