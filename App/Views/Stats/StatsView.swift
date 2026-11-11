import SwiftData
import SwiftUI

@MainActor
struct StatsView: View {
    @ObservedObject var store: TransactionScreenStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var month = ReportingMonth()
    @State private var current = ReportingMonth()
    @State private var showingMonthPicker = false
    @State private var selection: CategorySelection?

    private struct CategorySelection: Identifiable {
        let id: StatsService.CategoryKey
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        if let previous = month.previous { month = previous }
                    } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                        .disabled(month.previous == nil)
                        .accessibilityLabel("Tháng trước")
                    Button { showingMonthPicker = true } label: {
                        Text(month.title).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.accessibilityHint("Chọn tháng và năm")
                    Button {
                        if let next = month.next(upTo: current) { month = next }
                    } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                        .disabled(month.next(upTo: current) == nil)
                        .accessibilityLabel("Tháng sau")
                }
                .buttonStyle(.borderless)
                if month != current {
                    Button { month = current } label: { Text("Tháng này").frame(minHeight: 44) }
                        .buttonStyle(.borderless)
                }
            }
            // Read the store snapshot; detail queries use its refreshed context.
            StatsReportSections(store: store, month: month) { selection = CategorySelection(id: $0) }
                .environment(\.modelContext, store.statisticsContext ?? context)
                .id(store.snapshotVersion)
        }
        .gesture(DragGesture(minimumDistance: 60).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            if value.translation.width > 0, let previous = month.previous { month = previous }
            else if value.translation.width < 0, let next = month.next(upTo: current) { month = next }
        })
        .navigationTitle("Thống kê")
        .sheet(isPresented: $showingMonthPicker) {
            NavigationStack { StatsMonthPicker(month: $month, current: current, availableMonths: store.availableMonths) }
        }
        .sheet(item: $selection) { selection in
            NavigationStack {
                StatsCategoryDetailView(month: month, key: selection.id)
                    .environment(\.modelContext, store.statisticsContext ?? context)
                    .id(store.snapshotVersion)
            }
        }
        .onAppear(perform: updateCurrentMonth)
        .onChange(of: scenePhase) { _, phase in if phase == .active { updateCurrentMonth() } }
    }

    private func updateCurrentMonth() {
        current = ReportingMonth()
        month = month.clamped(to: current)
    }
}

@MainActor
private struct StatsMonthPicker: View {
    @Binding var month: ReportingMonth
    let current: ReportingMonth
    let availableMonths: [ReportingMonth]
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var selectedMonth: Int

    init(month: Binding<ReportingMonth>, current: ReportingMonth, availableMonths: [ReportingMonth]) {
        self.availableMonths = availableMonths
        _month = month
        self.current = current
        _year = State(initialValue: month.wrappedValue.year)
        _selectedMonth = State(initialValue: month.wrappedValue.month)
    }

    var body: some View {
        Form {
            if !availableMonths.isEmpty {
                Section("Tháng có giao dịch") {
                    ForEach(availableMonths.filter { $0 <= current }, id: \.self) { value in
                        Button(value.title) { month = value; dismiss() }
                    }
                }
            }
            Stepper("Năm \(String(year))", value: $year, in: 1...current.year).frame(minHeight: 44)
            Picker("Tháng", selection: $selectedMonth) {
                ForEach(1...12, id: \.self) { value in Text("Tháng \(value)").tag(value) }
            }.frame(minHeight: 44)
            Text("Không thể xem tháng sau tháng hiện tại.").font(.footnote).foregroundStyle(.secondary)
            Button {
                if let selected = try? ReportingMonth(year: year, month: selectedMonth) {
                    month = selected.clamped(to: current)
                    dismiss()
                }
            } label: { Text("Xem tháng").frame(maxWidth: .infinity, minHeight: 44) }
        }
        .navigationTitle("Chọn tháng")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } } }
    }
}

@MainActor
private struct StatsReportSections: View {
    @ObservedObject var store: TransactionScreenStore
    let month: ReportingMonth
    let select: (StatsService.CategoryKey) -> Void
    private var transactions: [Transaction] { store.transactions }
    private var categories: [Category] { store.categories }

    var body: some View {
        let comparison = try? StatsService.comparison(month: month, now: Date(), transactions: transactions)
        let result = Result { try StatsService.report(month: month, transactions: transactions) }
        switch result {
        case .success(let report):
            Section("Tóm tắt") {
                summary("Chênh lệch", amount: report.differenceText, negative: report.difference < 0, delta: comparison?.balance, label: comparison?.label)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        summary("Thu", amount: report.incomeText, delta: comparison?.income, label: comparison?.label)
                        summary("Chi", amount: report.expenseText, delta: comparison?.expense, label: comparison?.label)
                    }
                    VStack {
                        summary("Thu", amount: report.incomeText, delta: comparison?.income, label: comparison?.label)
                        summary("Chi", amount: report.expenseText, delta: comparison?.expense, label: comparison?.label)
                    }
                }
            }
            budgetSection
            if report.isEmpty { Section { EmptyState(image: "illus-empty-stats", title: "Tháng này chưa có giao dịch", message: "Đổi tháng để xem lịch sử", symbol: "chart.bar") } }
            categorySection("Chi theo danh mục", rows: report.expenses, empty: "Không có khoản chi.", report: report, comparison: comparison)
            if report.expense > 0 {
                Section("Chi theo ngày") {
                    switch Result(catching: { try StatsService.dailyExpenses(month: month, transactions: transactions) }) {
                    case .success(let days):
                        Card { StatsDailyChart(days: days, month: month, allowance: BudgetService.activeRule(for: .total, in: month, rules: store.budgetRules)
                            .map { StatsService.dailyAllowance(limit: $0.limit, month: month) }) }
                    case .failure(let error): Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red)
                    }
                }
            }
            categorySection("Thu theo danh mục", rows: report.incomes, empty: "Không có khoản thu.")
        case .failure(let error):
            Section { Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red) }
        }
    }

    private var budgetSection: some View {
        Section("Ngân sách") {
            if let error = store.budgetError(in: month) { Callout(level: .danger, title: "Chưa tính được ngân sách", message: error) }
            ForEach(store.progress(in: month), id: \.scope) { value in
                LedgerRow(icon: "target", title: BudgetPresentation.name(for: value.scope, categories: categories),
                          subtitle: value.level == .over ? "Đã vượt" : value.level == .warning ? "Sắp hết" : BudgetPresentation.remainingCompact(value),
                          amount: MoneyFormatter.compact(value.spent) + " / " + MoneyFormatter.compact(value.limit),
                          progress: value.fraction,
                          tint: value.level == .over ? .red : value.level == .warning ? .orange : .accentColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BudgetPresentation.voiceOver(value, name: BudgetPresentation.name(for: value.scope, categories: categories)))
                    .accessibilityValue(Text(value.fraction, format: .percent.precision(.fractionLength(0))))
            }
            NavigationLink("Sửa hạn mức") { BudgetListView(store: store) }
        }
    }

    private func summary(_ title: String, amount: String, negative: Bool = false, delta: StatsService.Comparison.Delta? = nil, label: String? = nil) -> some View {
        StatTile(title: title, value: amount, icon: title == "Thu" ? "arrow.up.circle" : title == "Chi" ? "arrow.down.circle" : "equal.circle", trend: delta.map { $0.text + " " + (label ?? "") }, valueTint: negative ? Color("Expense") : .primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amount), \(delta?.text ?? "") \(label ?? "")".replacingOccurrences(of: "₫", with: "đồng"))
    }

    private func categorySection(_ title: String, rows: [StatsService.CategoryTotal], empty: String, report: StatsService.Report? = nil, comparison: StatsService.Comparison? = nil) -> some View {
        Section(title) {
            if let report, report.expense > 0 { StatsCategoryChart(slices: StatsService.expenseSlices(report), total: report.expense) }
            if rows.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(rows) { row in
                Button { select(row.key) } label: {
                    LedgerRow(icon: row.icon, title: row.name,
                              subtitle: row.percentageText + (comparison?.expenseByCategory[row.key.categoryID].map { " · " + ($0.difference > 0 ? "+" : "") + MoneyFormatter.compact($0.difference) + " cùng kỳ" } ?? ""),
                              amount: MoneyFormatter.string(from: row.amount))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(MoneyFormatter.string(from: row.amount)), \(row.percentageText)")
                .accessibilityHint("Xem giao dịch trong tháng")
            }
        }
    }
}
