import SwiftUI

@MainActor
struct WalletListView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var store: TransactionScreenStore
    @State private var showingAdd = false
    @State private var showingTransfer = false
    @State private var transferSource: Wallet?
    @State private var archiveCandidate: Wallet?
    @State private var confirmingArchive = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tổng số dư").font(.headline)
                    Button { transferSource = nil; showingTransfer = true } label: { Label("Chuyển", systemImage: "arrow.left.arrow.right").frame(minHeight: 44) }
                    Text(store.totalBalance).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoButton(text: "Gồm cả số dư của ví đã lưu trữ.")
                }.accessibilityElement(children: .contain)
            }
            if let message = message ?? store.errorMessage { Text(message).foregroundStyle(.red) }
            if !store.wallets.contains(where: { !$0.isArchived && !$0.isPerson }) {
                EmptyState(image: "illus-empty-wallet", title: "Chưa có ví", message: "Thêm ví để bắt đầu", symbol: "wallet.bifold", actionTitle: "Thêm ví") { showingAdd = true }
            }
            Section("Đang dùng") {
                ForEach(store.wallets.filter { !$0.isArchived && !$0.isPerson }, id: \.id) { wallet in
                    activeWalletRow(wallet)
                }
            }
            Section("Công cụ") {
                tools
            }
        }
        .navigationTitle("Ví")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Thêm ví")
            }
        }
        .refreshable { reload() }
        .sheet(isPresented: $showingTransfer) { NavigationStack { TransferSheet(store: store, source: transferSource) } }
        .sheet(isPresented: $showingAdd) { NavigationStack { WalletFormView(store: store) } }
        .confirmationDialog("Lưu trữ ví \(archiveCandidate?.name ?? "")?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Lưu trữ") {
                guard let wallet = archiveCandidate else { return }
                do { try store.archiveWallet(wallet.id); message = nil }
                catch { message = TransactionPresentation.errorMessage(error) }
                archiveCandidate = nil
            }
            Button("Hủy", role: .cancel) { archiveCandidate = nil }
        } message: {
            if let wallet = archiveCandidate {
                Text("Số dư còn lại: \(store.balances[wallet.id] ?? "Không xác định")")
            }
        }
    }

    private func activeWalletRow(_ wallet: Wallet) -> some View {
                    NavigationLink { WalletDetailView(store: store, wallet: wallet) } label: { walletRow(wallet) }
                        .accessibilityHint("Xem lịch sử và thao tác với ví")
                        .contextMenu { Button("Chuyển tiền", systemImage: "arrow.left.arrow.right") { transferSource = wallet; showingTransfer = true } }
                        .accessibilityAction(named: Text("Lưu trữ ví")) { requestArchive(wallet) }
                        .swipeActions(allowsFullSwipe: false) {
                            Button { requestArchive(wallet) } label: { Label("Lưu trữ", systemImage: "archivebox") }
                                .tint(.orange)
                        }
    }
    private var tools: some View {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    NavigationLink { DebtListView(store: store) } label: { Card { IconRow(icon: "person.2", tint: .teal, title: "Sổ nợ") } }
                    NavigationLink { RecurringListView(store: store) } label: { Card { IconRow(icon: "arrow.triangle.2.circlepath", title: "Định kỳ", value: String(store.recurringRules.count)) } }
                    NavigationLink { BudgetListView(store: store) } label: { Card { IconRow(icon: "target", tint: .orange, title: "Ngân sách") } }
                    NavigationLink { CategoryListView(store: store) } label: { Card { IconRow(icon: "tag", tint: .purple, title: "Danh mục") } }
                    NavigationLink { archivedWallets } label: { Card { IconRow(icon: "archivebox", tint: .secondary, title: "Đã lưu trữ", value: String(store.wallets.filter { $0.isArchived && !$0.isPerson }.count)) } }
                }.buttonStyle(.plain)
    }

    private var archivedWallets: some View {
        List {
            ForEach(store.wallets.filter { $0.isArchived && !$0.isPerson }, id: \.id) { wallet in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { WalletDetailView(store: store, wallet: wallet) } label: { walletRow(wallet) }
                    Button("Khôi phục \(wallet.name)") { restore(wallet) }.frame(minHeight: 44)
                }
            }
        }.navigationTitle("Ví đã lưu trữ")
    }

    private func walletRow(_ wallet: Wallet) -> some View {
        WalletCard(wallet: wallet, balance: store.balanceValues[wallet.id])
    }

    private func requestArchive(_ wallet: Wallet) { archiveCandidate = wallet; confirmingArchive = true }
    private func restore(_ wallet: Wallet) {
        do { try store.restoreWallet(wallet.id); message = nil }
        catch { message = TransactionPresentation.errorMessage(error) }
    }
    private func reload() {
        do { try store.reload(); message = nil }
        catch { message = TransactionPresentation.errorMessage(error) }
    }
}
