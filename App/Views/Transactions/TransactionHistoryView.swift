import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var editing: Transaction?
    @State private var pendingDeletion: Transaction?
    @State private var confirmingDeletion = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        Button { editing = transaction } label: { row(transaction) }
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

    private func row(_ transaction: Transaction) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    description(transaction)
                    amount(transaction)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        description(transaction)
                        Spacer(minLength: 8)
                        amount(transaction)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        description(transaction)
                        amount(transaction)
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
    }

    private func description(_ transaction: Transaction) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: transaction.kindRaw == "transfer" ? "arrow.left.arrow.right" : transaction.category?.icon ?? "tag")
                .foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(TransactionPresentation.title(transaction))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(transaction.wallet?.name ?? "Ví không xác định")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !transaction.note.isEmpty {
                    Text(transaction.note).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func amount(_ transaction: Transaction) -> some View {
        Text(TransactionPresentation.amount(transaction))
            .font(.headline).monospacedDigit()
            .foregroundStyle(transaction.kindRaw == "income" ? Color.green : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
