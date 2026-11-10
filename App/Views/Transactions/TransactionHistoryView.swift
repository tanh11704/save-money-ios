import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var editing: Transaction?
    @State private var pendingDeletion: Transaction?
    @State private var confirmingDeletion = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tổng số dư").font(.headline)
                    Text(store.totalBalance).font(.title2).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("history.totalBalance")
                }
                .accessibilityElement(children: .combine)
            }
            if let message = store.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Tải lại dữ liệu") { reload() }.frame(minHeight: 44)
                }
            }
            if store.transactions.isEmpty {
                Text("Chưa có giao dịch. Sang tab Thêm để ghi khoản đầu tiên.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
            }
            ForEach(TransactionGrouping.group(store.transactions)) { day in
                Section(TransactionGrouping.title(for: day.date)) {
                    ForEach(day.transactions, id: \.id) { transaction in
                        Button { editing = transaction } label: { TransactionRow(transaction: transaction) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(TransactionPresentation.accessibilityLabel(transaction))
                            .accessibilityValue([transaction.wallet?.name ?? "", transaction.note].filter { !$0.isEmpty }.joined(separator: ", "))
                            .accessibilityHint("Chạm hai lần để sửa giao dịch")
                            .accessibilityAction(named: Text("Xóa giao dịch")) { requestDeletion(transaction) }
                            .swipeActions(allowsFullSwipe: false) {
                                Button(role: .destructive) { requestDeletion(transaction) } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Lịch sử")
        .refreshable { reload() }
        .sheet(item: $editing) { transaction in
            NavigationStack {
                TransactionFormView(store: store, original: transaction)
            }
        }
        .confirmationDialog("Xóa giao dịch này?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Xóa giao dịch", role: .destructive) {
                if let transaction = pendingDeletion { store.delete(transaction.id) }
                pendingDeletion = nil
            }
            Button("Hủy", role: .cancel) { pendingDeletion = nil }
        } message: {
            if let transaction = pendingDeletion {
                Text("\(TransactionPresentation.title(transaction)) · \(TransactionPresentation.amount(transaction)). Thao tác này không thể hoàn tác.")
            }
        }
    }

    private func requestDeletion(_ transaction: Transaction) {
        pendingDeletion = transaction
        confirmingDeletion = true
    }

    private func reload() {
        do { try store.reload() }
        catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
