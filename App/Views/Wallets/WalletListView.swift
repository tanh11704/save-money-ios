import SwiftUI

@MainActor
struct WalletListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var showingAdd = false
    @State private var showingTransfer = false
    @State private var transferSource: Wallet?
    @State private var editing: Wallet?
    @State private var archiveCandidate: Wallet?
    @State private var confirmingArchive = false
    @State private var archivedExpanded = false
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
                }.accessibilityElement(children: .combine)
            }
            if let message = message ?? store.errorMessage { Text(message).foregroundStyle(.red) }
            if !store.wallets.contains(where: { !$0.isArchived }) {
                EmptyState(image: "illus-empty-wallet", title: "Chưa có ví", message: "Thêm ví để bắt đầu", symbol: "wallet.bifold", actionTitle: "Thêm ví") { showingAdd = true }
            }
            Section("Đang dùng") {
                ForEach(store.wallets.filter { !$0.isArchived }, id: \.id) { wallet in
                    NavigationLink { WalletDetailView(store: store, wallet: wallet) } label: { walletRow(wallet) }
                        .accessibilityHint("Xem lịch sử và thao tác với ví")
                        .contextMenu { Button("Chuyển tiền", systemImage: "arrow.left.arrow.right") { transferSource = wallet; showingTransfer = true } }
                        .accessibilityAction(named: Text("Lưu trữ ví")) { requestArchive(wallet) }
                        .swipeActions(allowsFullSwipe: false) {
                            Button { requestArchive(wallet) } label: { Label("Lưu trữ", systemImage: "archivebox") }
                                .tint(.orange)
                        }
                }
            }
            Section {
                DisclosureGroup("Đã lưu trữ (\(store.wallets.filter { $0.isArchived }.count))", isExpanded: $archivedExpanded) {
                    ForEach(store.wallets.filter { $0.isArchived }, id: \.id) { wallet in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { editing = wallet } label: { walletRow(wallet) }.buttonStyle(.plain)
                            Button { restore(wallet) } label: {
                                Text("Khôi phục \(wallet.name)").frame(minHeight: 44)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 44)
            }
            Section("Công cụ") {
                NavigationLink { RecurringListView(store: store) } label: {
                    IconRow(icon: "arrow.triangle.2.circlepath", title: "Định kỳ", value: String(store.recurringRules.count))
                }
                NavigationLink { BudgetListView(store: store) } label: {
                    IconRow(icon: "target", tint: .orange, title: "Ngân sách")
                }
                NavigationLink { CategoryListView(store: store) } label: {
                    IconRow(icon: "tag", tint: .purple, title: "Danh mục")
                }
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
        .sheet(item: $editing) { wallet in NavigationStack { WalletFormView(store: store, original: wallet) } }
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
