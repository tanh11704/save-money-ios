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
            // Query results are never cached. Replacing the read context after a
            // save also avoids stale identity-map objects from a different context.
            StatsReportSections(month: month) { selection = CategorySelection(id: $0) }
                .environment(\.modelContext, store.statisticsContext ?? context)
                .id(store.snapshotVersion)
        }
        .navigationTitle("Thống kê")
        .sheet(isPresented: $showingMonthPicker) {
            NavigationStack { StatsMonthPicker(month: $month, current: current) }
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
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var selectedMonth: Int

    init(month: Binding<ReportingMonth>, current: ReportingMonth) {
        _month = month
        self.current = current
        _year = State(initialValue: month.wrappedValue.year)
        _selectedMonth = State(initialValue: month.wrappedValue.month)
    }

    var body: some View {
        Form {
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
    let month: ReportingMonth
    let select: (StatsService.CategoryKey) -> Void
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @Query private var categories: [Category]

    var body: some View {
        let result = Result { try StatsService.report(month: month, transactions: transactions) }
        switch result {
        case .success(let report):
            Section("Tóm tắt") {
                summary("Tổng thu", amount: report.incomeText, negative: false)
                summary("Tổng chi", amount: report.expenseText, negative: false)
                summary("Chênh lệch", amount: report.differenceText, negative: report.difference < 0)
            }
            if report.expense > 0 {
                Section("Chi theo ngày") {
                    switch Result(catching: { try StatsService.dailyExpenses(month: month, transactions: transactions) }) {
                    case .success(let days):
                        StatsDailyChart(days: days, allowance: BudgetService.activeRule(for: .total, in: month, rules: budgets.compactMap(\.rule))
                            .map { StatsService.dailyAllowance(limit: $0.limit, month: month) })
                    case .failure(let error): Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red)
                    }
                }
            }
            budgetSection
            if report.isEmpty { Section { Text("Tháng này chưa có giao dịch.").foregroundStyle(.secondary) } }
            categorySection("Chi theo danh mục", rows: report.expenses, empty: "Không có khoản chi.", report: report)
            categorySection("Thu theo danh mục", rows: report.incomes, empty: "Không có khoản thu.")
        case .failure(let error):
            Section { Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var budgetSection: some View {
        switch Result(catching: { try BudgetService.progress(month: month, rules: budgets.compactMap(\.rule), transactions: transactions) }) {
        case .success(let progress):
            if !progress.isEmpty {
                Section("Ngân sách") {
                    ForEach(progress, id: \.scope) { value in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(BudgetPresentation.name(for: value.scope, categories: categories)).font(.headline)
                            ProgressView(value: value.fraction)
                                .tint(value.level == .over ? Color.red : value.level == .warning ? Color.orange : Color.accentColor)
                            Text(BudgetPresentation.usage(value))
                                .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            Text(BudgetPresentation.remaining(value)).monospacedDigit()
                            if value.level != .normal {
                                Text(value.level == .over ? "Đã vượt" : "Sắp hết")
                                    .foregroundStyle(value.level == .over ? Color.red : Color.orange)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(BudgetPresentation.voiceOver(value, name: BudgetPresentation.name(for: value.scope, categories: categories)))
                    }
                }
            }
        case .failure(let error):
            Section("Ngân sách") { Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red) }
        }
    }

    private func summary(_ title: String, amount: String, negative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(amount).font(.title2).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(negative ? Color.red : Color.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amount)")
    }

    private func categorySection(_ title: String, rows: [StatsService.CategoryTotal], empty: String, report: StatsService.Report? = nil) -> some View {
        Section(title) {
            if let report, report.expense > 0 { StatsCategoryChart(slices: StatsService.expenseSlices(report), total: report.expense) }
            if rows.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(rows) { row in
                Button { select(row.key) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(row.name, systemImage: row.icon)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(MoneyFormatter.string(from: row.amount)).font(.headline).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.percentageText).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(MoneyFormatter.string(from: row.amount)), \(row.percentageText)")
                .accessibilityHint("Xem giao dịch trong tháng")
            }
        }
    }
}
