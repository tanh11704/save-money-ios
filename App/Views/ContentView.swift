import SwiftData
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TransactionScreenStore()
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
