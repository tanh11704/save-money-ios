import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var filter = HistoryFilter()
    var onAdd: (() -> Void)? = nil
    @State private var editing: Transaction?
    @State private var pendingDeletion: Transaction?
    @State private var confirmingDeletion = false

    var body: some View {
        List {
            Section {
                StatTile(title: "Tổng số dư", value: store.totalBalance, icon: "wallet.bifold")
                    .accessibilityIdentifier("history.totalBalance")
                if let report = try? StatsService.report(month: ReportingMonth(), transactions: store.transactions) {
                    ViewThatFits(in: .horizontal) {
                        HStack { StatTile(title: "Thu tháng này", value: report.incomeText, icon: "arrow.up.circle"); StatTile(title: "Chi tháng này", value: report.expenseText, icon: "arrow.down.circle") }
                        VStack { StatTile(title: "Thu tháng này", value: report.incomeText, icon: "arrow.up.circle"); StatTile(title: "Chi tháng này", value: report.expenseText, icon: "arrow.down.circle") }
                    }
                }
                filters
                .accessibilityElement(children: .combine)
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
            if !store.transactions.isEmpty && filter.apply(to: store.transactions).isEmpty {
                EmptyState(image: "illus-empty-search", title: "Không có kết quả", message: "Thử đổi tìm kiếm hoặc bộ lọc", symbol: "magnifyingglass", actionTitle: "Xóa bộ lọc") { filter = HistoryFilter() }
            }
            ForEach(TransactionGrouping.group(filter.apply(to: store.transactions))) { day in
                Section {
                    ForEach(day.transactions, id: \.id) { transaction in
                        transactionRow(transaction)
                    }
                } header: {
                    HStack { Text(TransactionGrouping.title(for: day.date)); Spacer(); if let expense = HistoryFilter.expenseText(for: day.transactions) { Text(expense).monospacedDigit() } }
                }
            }
        }
        .searchable(text: $filter.query, prompt: "Ghi chú hoặc danh mục")
        .scrollDismissesKeyboard(.interactively)
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
            .swipeActions(allowsFullSwipe: false) {
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
                    ForEach(Array(Set(store.transactions.map { ReportingMonth(containing: $0.date) })).sorted { $0.interval.start > $1.interval.start }, id: \.self) { month in
                        Button(month.title) { filter.month = month }
                    }
                } label: { Label(filter.month?.title ?? "Tháng", systemImage: "calendar").frame(minHeight: 44) }
                if filter.month != nil { Button { filter.month = nil } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Bỏ lọc tháng") }
            }.buttonStyle(.bordered)
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
