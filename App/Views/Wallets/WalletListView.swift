import SwiftUI

@MainActor
struct WalletListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var showingAdd = false
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
                    Text(store.totalBalance).font(.largeTitle).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Gồm cả số dư của ví đã lưu trữ.").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
            if let message = message ?? store.errorMessage { Text(message).foregroundStyle(.red) }
            if !store.wallets.contains(where: { !$0.isArchived }) {
                Text("Chưa có ví. Thêm ví đầu tiên để bắt đầu.").foregroundStyle(.secondary)
            }
            Section("Đang dùng") {
                ForEach(store.wallets.filter { !$0.isArchived }, id: \.id) { wallet in
                    Button { editing = wallet } label: { walletRow(wallet) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Chạm hai lần để sửa ví")
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
            Section {
                NavigationLink { BudgetListView(store: store) } label: {
                    Label("Ngân sách", systemImage: "chart.bar").frame(minHeight: 44)
                }
                NavigationLink { CategoryListView(store: store) } label: {
                    Label("Quản lý danh mục", systemImage: "tag").frame(minHeight: 44)
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
        .sheet(isPresented: $showingAdd) { NavigationStack { WalletFormView(store: store) } }
        .sheet(item: $editing) { wallet in NavigationStack { WalletFormView(store: store, original: wallet) } }
        .confirmationDialog("Lưu trữ ví?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Lưu trữ") {
                guard let wallet = archiveCandidate else { return }
                do { try store.archiveWallet(wallet.id); message = nil }
                catch { message = TransactionPresentation.errorMessage(error) }
                archiveCandidate = nil
            }
            Button("Hủy", role: .cancel) { archiveCandidate = nil }
        } message: {
            if let wallet = archiveCandidate {
                Text("Không hiện khi nhập mới. Lịch sử và số dư giữ nguyên. Số dư còn lại: \(store.balances[wallet.id] ?? "Không xác định").")
            }
        }
    }

    private func walletRow(_ wallet: Wallet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(wallet.name, systemImage: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text((WalletKind(rawValue: wallet.kindRaw) ?? .other).title).font(.caption).foregroundStyle(.secondary)
            Text(store.balances[wallet.id] ?? "Chưa tính được")
                .font(.headline).monospacedDigit()
                .foregroundStyle((store.balanceValues[wallet.id] ?? 0) < 0 ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
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
