import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore
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
                        row(transaction)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(TransactionPresentation.accessibilityLabel(transaction))
                    }
                }
            }
        }
        .navigationTitle("Lịch sử")
        .refreshable { reload() }
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
                amount(transaction).frame(maxWidth: .infinity, alignment: .trailing)
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

    private func reload() {
        do { try store.reload() }
        catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
