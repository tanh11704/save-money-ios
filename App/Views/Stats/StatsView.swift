import SwiftData
import SwiftUI

@MainActor
struct StatsView: View {
    @ObservedObject var store: TransactionScreenStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("SaveMoney.stats.periodKind") private var kindRaw = StatsPeriodKind.month.rawValue
    @AppStorage(MonthCycle.startDayKey) private var monthStartDay = 1
    @State private var period = StatsPeriod(kind: .month)
    @State private var current = StatsPeriod(kind: .month)
    @State private var showingMonthPicker = false
    @State private var showingWeekPicker = false
    @State private var selection: CategorySelection?

    private struct CategorySelection: Identifiable {
        let id: StatsService.CategoryKey
    }

    private var kind: StatsPeriodKind { StatsPeriodKind(rawValue: kindRaw) ?? .month }
    private var unit: String { kind == .week ? "Tuần" : "Tháng" }

    var body: some View {
        List {
            Section {
                Picker("Xem theo", selection: Binding(get: { kind }, set: { switchKind(to: $0) })) {
                    ForEach(StatsPeriodKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityIdentifier("stats.periodKind")
                HStack(alignment: .center, spacing: 8) {
                    Button { period = period.previous } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("\(unit) trước")
                    Button { if kind == .week { showingWeekPicker = true } else { showingMonthPicker = true } } label: {
                        Text(period.title).font(.headline).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.accessibilityHint(kind == .week ? "Chọn tuần" : "Chọn tháng và năm")
                    Button { if let next = period.next(upTo: current) { period = next } } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(period.next(upTo: current) == nil)
                    .accessibilityLabel("\(unit) sau")
                }
                .buttonStyle(.borderless)
                if period != current {
                    Button { period = current } label: { Text("\(unit) này").frame(minHeight: 44) }
                        .buttonStyle(.borderless)
                }
            }
            // Read the store snapshot; detail queries use its refreshed context.
            StatsReportSections(store: store, period: period, select: { selection = CategorySelection(id: $0) },
                                selectPeriod: show)
                .environment(\.modelContext, store.statisticsContext ?? context)
                .id(store.snapshotVersion)
        }
        .gesture(DragGesture(minimumDistance: 60).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            if value.translation.width > 0 { period = period.previous }
            else if value.translation.width < 0, let next = period.next(upTo: current) { period = next }
        })
        .navigationTitle("Thống kê")
        .sheet(isPresented: $showingMonthPicker) {
            NavigationStack {
                StatsMonthPicker(month: Binding(get: { period.month }, set: { period = StatsPeriod(month: $0) }),
                                 current: current.month, availableMonths: store.availableMonths)
            }
            .appSheet(.medium)
        }
        .sheet(isPresented: $showingWeekPicker) {
            NavigationStack {
                StatsWeekPicker(period: $period, current: current)
            }
            .appSheet(.medium)
        }
        .sheet(item: $selection) { selection in
            NavigationStack {
                StatsCategoryDetailView(period: period, key: selection.id)
                    .environment(\.modelContext, store.statisticsContext ?? context)
                    .id(store.snapshotVersion)
            }
        }
        .onAppear(perform: updateCurrent)
        .onChange(of: monthStartDay) { _, _ in
            // A stored month period keeps its old interval; rebuild it around the same day.
            let anchor = period.contains(Date()) ? Date() : period.lastDay
            current = StatsPeriod(kind: kind, containing: Date())
            period = kind == .month ? min(StatsPeriod(kind: .month, containing: anchor), current) : period
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { updateCurrent() } }
    }

    private func updateCurrent() {
        current = StatsPeriod(kind: kind, containing: Date())
        period = period.kind == kind ? min(period, current) : current
    }

    /// Jump to a period from a chart or link, switching week ⇄ month when needed.
    private func show(_ target: StatsPeriod) {
        if target.kind != kind {
            kindRaw = target.kind.rawValue
            current = StatsPeriod(kind: target.kind, containing: Date())
        }
        period = min(target, current)
    }

    /// Keep looking at roughly the same time when switching week ⇄ month.
    private func switchKind(to newKind: StatsPeriodKind) {
        guard newKind != kind else { return }
        let anchor = period.contains(Date()) ? Date() : period.lastDay
        kindRaw = newKind.rawValue
        current = StatsPeriod(kind: newKind, containing: Date())
        period = min(StatsPeriod(kind: newKind, containing: anchor), current)
    }
}

@MainActor
private struct StatsWeekPicker: View {
    @Binding var period: StatsPeriod
    let current: StatsPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(period: Binding<StatsPeriod>, current: StatsPeriod) {
        _period = period
        self.current = current
        _date = State(initialValue: period.wrappedValue.interval.start)
    }

    var body: some View {
        let chosen = StatsPeriod(kind: .week, containing: date)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                DatePicker("Ngày trong tuần", selection: $date, in: ...current.lastDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, StatsPeriod.weekCalendar)
                Label(chosen.title, systemImage: "calendar").font(.headline).monospacedDigit()
            }.padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryActionBar(title: "Xem tuần này", systemImage: "chart.bar") {
                period = min(chosen, current)
                dismiss()
            }
        }
        .navigationTitle("Chọn tuần")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } } }
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
    let period: StatsPeriod
    let select: (StatsService.CategoryKey) -> Void
    var selectPeriod: (StatsPeriod) -> Void = { _ in }
    private var month: ReportingMonth { period.month }
    private var isWeek: Bool { period.kind == .week }
    private var transactions: [Transaction] { store.transactions }
    private var categories: [Category] { store.categories }

    var body: some View {
        let comparison = try? StatsService.comparison(period: period, now: Date(), transactions: transactions)
        let result = Result { try StatsService.report(period: period, transactions: transactions) }
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
            // Budgets are monthly; the week view links to the month instead of mixing periods.
            if isWeek {
                if !store.progress(in: month).isEmpty {
                    Section {
                        Button { selectPeriod(StatsPeriod(month: ReportingMonth(containing: period.lastDay))) } label: {
                            IconRow(icon: "target", tint: .orange, title: "Ngân sách theo tháng", value: "Xem tháng")
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                budgetSection
            }
            if report.isEmpty {
                Section { EmptyState(image: "illus-empty-stats", title: isWeek ? "Tuần này chưa có giao dịch" : "Tháng này chưa có giao dịch",
                                     message: isWeek ? "Đổi tuần để xem lịch sử" : "Đổi tháng để xem lịch sử", symbol: "chart.bar") }
            }
            categorySection("Chi theo danh mục", rows: report.expenses, empty: "Không có khoản chi.", report: report, comparison: comparison)
            if report.expense > 0 {
                Section("Chi theo ngày") {
                    switch Result(catching: { try StatsService.dailyExpenses(period: period, transactions: transactions) }) {
                    case .success(let days):
                        Card { StatsDailyChart(days: days, period: period, allowance: BudgetService.activeRule(for: .total, in: month, rules: store.budgetRules)
                            .map { StatsService.dailyAllowance(limit: $0.limit, month: month) }) }
                    case .failure(let error): Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red)
                    }
                }
            }
            trendSection
            categorySection("Thu theo danh mục", rows: report.incomes, empty: "Không có khoản thu.")
        case .failure(let error):
            Section { Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red) }
        }
    }

    @State private var showsUnspentBudgets = false

    @ViewBuilder private var trendSection: some View {
        let count = isWeek ? 8 : 6
        if let points = try? StatsService.trend(ending: period, count: count, transactions: transactions),
           points.contains(where: { $0.income != 0 || $0.expense != 0 }) {
            Section(isWeek ? "\(count) tuần gần nhất" : "\(count) tháng gần nhất") {
                Card { StatsTrendChart(points: points, selected: period, onSelect: selectPeriod) }
            }
        }
    }

    private var budgetSection: some View {
        let progress = store.progress(in: month)
        // Rows with no spending are folded away so the section shows what needs attention.
        let active = progress.filter { $0.scope == .total || $0.spent != 0 }
        let unspent = progress.filter { $0.scope != .total && $0.spent == 0 }
        return Section("Ngân sách") {
            if let error = store.budgetError(in: month) { Callout(level: .danger, title: "Chưa tính được ngân sách", message: error) }
            ForEach(active, id: \.scope) { budgetRow($0) }
            if !unspent.isEmpty {
                DisclosureGroup(isExpanded: $showsUnspentBudgets) {
                    ForEach(unspent, id: \.scope) { budgetRow($0) }
                } label: {
                    Text("\(unspent.count) danh mục chưa chi").foregroundStyle(.secondary)
                }.frame(minHeight: 44)
            }
            NavigationLink { BudgetListView(store: store) } label: {
                IconRow(icon: "slider.horizontal.3", tint: .gray, title: "Sửa hạn mức")
            }
        }
    }

    private func budgetRow(_ value: BudgetService.Progress) -> some View {
        let category: Category? = {
            guard case .category(let id) = value.scope else { return nil }
            return categories.first { $0.id == id }
        }()
        let tint: Color = value.level == .over ? Color("Expense") : value.level == .warning ? .orange
            : category.map { CategoryStyle.tint(for: $0.icon) } ?? .accentColor
        return LedgerRow(icon: category?.icon ?? "target", title: BudgetPresentation.name(for: value.scope, categories: categories),
                  subtitle: value.level == .over ? "Đã vượt" : value.level == .warning ? "Sắp hết · " + BudgetPresentation.remainingCompact(value) : BudgetPresentation.remainingCompact(value),
                  amount: MoneyFormatter.compact(value.spent) + " / " + MoneyFormatter.compact(value.limit),
                  progress: value.fraction, tint: tint, categoryIcon: category != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BudgetPresentation.voiceOver(value, name: BudgetPresentation.name(for: value.scope, categories: categories)))
            .accessibilityValue(Text(value.fraction, format: .percent.precision(.fractionLength(0))))
    }

    private func summary(_ title: String, amount: String, negative: Bool = false, delta: StatsService.Comparison.Delta? = nil, label: String? = nil) -> some View {
        StatTile(title: title, value: amount, icon: title == "Thu" ? "arrow.up.circle" : title == "Chi" ? "arrow.down.circle" : "equal.circle", trend: delta.flatMap { $0.isEmpty ? nil : $0.badgeText + " " + (label ?? "") }, valueTint: negative ? Color("Expense") : .primary)
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
                              subtitle: row.percentageText + (comparison?.expenseByCategory[row.key.categoryID].flatMap { $0.difference == 0 ? nil : " · " + ($0.difference > 0 ? "+" : "") + MoneyFormatter.compact($0.difference) + " cùng kỳ" } ?? ""),
                              amount: MoneyFormatter.string(from: row.amount), categoryIcon: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(MoneyFormatter.string(from: row.amount)), \(row.percentageText)")
                .accessibilityHint("Xem giao dịch trong tháng")
            }
        }
    }
}
