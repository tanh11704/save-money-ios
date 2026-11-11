import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var filter = HistoryFilter()
    var onAdd: (() -> Void)? = nil
    @State private var editing: Transaction?
    @State private var duplicating: Transaction?
    @State private var filtered: [Transaction] = []
    @State private var days: [TransactionGrouping.Day] = []
    @State private var dayFlows: [Date: String] = [:]
    @State private var dayFlowLabels: [Date: String] = [:]
    private struct RefreshKey: Equatable { let filter: HistoryFilter; let snapshot: UUID }

    var body: some View {
        List {
            Section {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tổng số dư").font(.subheadline).foregroundStyle(.secondary)
                        Text(store.totalBalance).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                        if let report = store.currentMonthReport {
                            Text("Tháng \(ReportingMonth().month) · Thu +\(MoneyFormatter.compact(report.income)) · Chi −\(MoneyFormatter.compact(report.expense))")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Tháng \(ReportingMonth().month), thu \(report.incomeText), chi \(report.expenseText)")
                        }
                    }
                }.accessibilityIdentifier("history.totalBalance")
            }
            if let message = store.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Tải lại dữ liệu") { reload() }.frame(minHeight: 44)
                }
            }
            if store.transactions.isEmpty {
                EmptyState(image: "illus-empty-history", title: "Chưa có giao dịch", message: "Bắt đầu ghi chi tiêu", actionTitle: "Ghi khoản đầu tiên", action: onAdd)
            }
            if !store.transactions.isEmpty && filtered.isEmpty {
                EmptyState(image: "illus-empty-search", title: "Không có kết quả", message: "Thử đổi tìm kiếm hoặc bộ lọc", symbol: "magnifyingglass", actionTitle: "Xóa bộ lọc") { filter = HistoryFilter() }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.transactions, id: \.id) { transaction in
                        transactionRow(transaction)
                    }
                } header: {
                    HStack { Text(TransactionGrouping.title(for: day.date)); Spacer(); if let expense = dayFlows[day.date] { Text(expense).monospacedDigit().accessibilityLabel(dayFlowLabels[day.date] ?? expense) } }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filters.background(.bar) }
        .searchable(text: $filter.query, prompt: "Người, ví, danh mục, số tiền")
        .task(id: RefreshKey(filter: filter, snapshot: store.snapshotVersion)) {
            if !filter.query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let result = filter.apply(to: store.transactions)
            filtered = result
            let grouped = TransactionGrouping.group(result)
            days = grouped
            dayFlows = Dictionary(uniqueKeysWithValues: grouped.compactMap { day in
                HistoryFilter.flowText(for: day.transactions).map { (day.date, $0) }
            })
            dayFlowLabels = Dictionary(uniqueKeysWithValues: grouped.map { ($0.date, HistoryFilter.flowAccessibilityLabel(for: $0.transactions)) })
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Lịch sử")
        .refreshable { reload() }
        .sheet(item: $editing) { transaction in
            NavigationStack {
                TransactionFormView(store: store, original: transaction)
            }
        }
        .sheet(item: $duplicating) { transaction in
            NavigationStack { TransactionFormView(store: store, template: transaction) }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let debt = store.debtLabels[transaction.id]
        let label: String
        if let debt { label = debt.title + ", " + TransactionPresentation.amount(transaction) }
        else { label = TransactionPresentation.accessibilityLabel(transaction) }
        return Button { editing = transaction } label: { TransactionRow(transaction: transaction, debt: debt) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue([transaction.wallet?.name ?? "", transaction.note].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityHint("Chạm hai lần để sửa giao dịch")
            .accessibilityAction(named: Text("Xóa giao dịch")) { requestDeletion(transaction) }
            .contextMenu {
                Button("Ghi lại khoản này", systemImage: "doc.on.doc") { duplicating = transaction }
            }
            .accessibilityAction(named: Text("Ghi lại khoản này")) { duplicating = transaction }
            .swipeActions(allowsFullSwipe: false) {
                Button { duplicating = transaction } label: { Label("Ghi lại", systemImage: "doc.on.doc") }.tint(.blue)
                Button { editing = transaction } label: { Label("Sửa", systemImage: "pencil") }.tint(.accentColor)
                Button(role: .destructive) { requestDeletion(transaction) } label: { Label("Xóa", systemImage: "trash") }
            }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Menu {
                    Button("Tất cả ví") { filter.walletID = nil }
                    ForEach(store.wallets, id: \.id) { wallet in Button(wallet.name) { filter.walletID = wallet.id } }
                } label: { Label(store.wallets.first { $0.id == filter.walletID }?.name ?? "Ví", systemImage: "wallet.bifold").frame(minHeight: 44) }
                if filter.walletID != nil { Button { filter.walletID = nil } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Bỏ lọc ví") }
                Menu {
                    Button("Tất cả danh mục") { filter.categoryID = nil }
                    ForEach(store.categories, id: \.id) { category in Button(category.name) { filter.categoryID = category.id } }
                } label: { Label(store.categories.first { $0.id == filter.categoryID }?.name ?? "Danh mục", systemImage: "tag").frame(minHeight: 44) }
                if filter.categoryID != nil { Button { filter.categoryID = nil } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Bỏ lọc danh mục") }
                Menu {
                    Button("Mọi tháng") { filter.month = nil }
                    ForEach(store.availableMonths, id: \.self) { month in
                        Button(month.title) { filter.month = month }
                    }
                } label: { Label(filter.month?.title ?? "Tháng", systemImage: "calendar").frame(minHeight: 44) }
                if filter.month != nil { Button { filter.month = nil } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Bỏ lọc tháng") }
            }.font(.subheadline).controlSize(.small).buttonStyle(.bordered)
                .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func requestDeletion(_ transaction: Transaction) {
        store.delete(transaction.id)
    }

    private func reload() {
        do { try store.reload() }
        catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
