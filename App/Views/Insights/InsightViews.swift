import SwiftUI

extension ReportingMonth: Identifiable {
    var id: String { CycleSummaryTracker.identifier(self) }
}

private func spoken(_ amount: Int64) -> String { MoneyFormatter.string(from: amount).replacingOccurrences(of: "₫", with: "đồng") }

/// Digits-only money input for forms; the formatted value is shown next to it.
private struct MoneyTextField: View {
    let title: String
    @Binding var amount: Int64?
    var prompt = "0"
    @State private var text = ""
    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: $text)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                .onChange(of: text) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(12))
                    if digits != value { text = digits }
                    amount = Int64(digits).flatMap { $0 > 0 && $0 <= MoneyFormatter.maximumInput ? $0 : nil }
                }
        }
        .frame(minHeight: 44)
        .onAppear { if let amount { text = String(amount) } }
        // Values loaded by the parent after this field appeared.
        .onChange(of: amount) { _, value in if let value, Int64(text) != value { text = String(value) } }
        .accessibilityValue(amount.map(spoken) ?? "Chưa nhập")
    }
}

// MARK: - Flexible daily allowance

/// "Hôm nay còn được tiêu": the running cycle's leftover budget spread over the days left.
struct FlexibleAllowanceCard: View {
    let allowance: StatsService.FlexibleAllowance
    var compact = false

    private var tint: Color { allowance.leftToday < 0 ? Color("Expense") : allowance.perDay == 0 ? .orange : Color("Income") }

    var body: some View {
        if compact {
            Text(allowance.leftToday >= 0
                 ? "Hôm nay còn được tiêu \(MoneyFormatter.compact(allowance.leftToday))"
                 : "Hôm nay đã vượt \(MoneyFormatter.compact(-allowance.leftToday))")
                .font(.caption.weight(.semibold)).foregroundStyle(tint)
                .accessibilityLabel(allowance.leftToday >= 0 ? "Hôm nay còn được tiêu \(spoken(allowance.leftToday))" : "Hôm nay đã vượt \(spoken(-allowance.leftToday))")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(allowance.leftToday >= 0 ? "Hôm nay còn được tiêu" : "Hôm nay đã vượt", systemImage: "sun.max")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    InfoButton(text: "Lấy hạn mức tổng còn lại từ đầu hôm nay, chia đều cho \(allowance.daysLeft) ngày còn lại của kỳ (tính cả hôm nay). Hôm qua chi nhiều thì hôm nay ít đi, tiết kiệm thì được nhiều hơn.")
                }
                Text(MoneyFormatter.string(from: abs(allowance.leftToday)))
                    .font(.system(.title, design: .rounded).bold()).monospacedDigit().foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("≈ \(MoneyFormatter.compact(allowance.perDay))/ngày · còn \(allowance.daysLeft) ngày · hôm nay đã chi \(MoneyFormatter.compact(allowance.spentToday))")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if allowance.perDay == 0 {
                    Text("Đã dùng hết hạn mức tổng của kỳ này.").font(.caption.weight(.semibold)).foregroundStyle(Color("Expense"))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - End-of-cycle summary

struct CycleSummaryView: View {
    @ObservedObject var store: TransactionScreenStore
    let month: ReportingMonth
    var onDone: (() -> Void)? = nil

    var body: some View {
        List {
            switch Result(catching: { try CycleSummary.make(month: month, transactions: store.transactions, rules: store.budgetRules) }) {
            case .success(let summary): content(summary)
            case .failure(let error): Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red)
            }
        }
        .navigationTitle("Tổng kết kỳ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone { ToolbarItem(placement: .confirmationAction) { Button("Xong", action: onDone).frame(minHeight: 44) } }
        }
    }

    @ViewBuilder private func content(_ summary: CycleSummary) -> some View {
        let report = summary.report
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(month.title).font(.headline)
                Text(summary.saved >= 0 ? "Bạn đã để dành" : "Chi nhiều hơn thu").font(.subheadline).foregroundStyle(.secondary)
                Text(MoneyFormatter.string(from: abs(summary.saved)))
                    .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    .foregroundStyle(summary.saved >= 0 ? Color("Income") : Color("Expense"))
                    .lineLimit(1).minimumScaleFactor(0.4)
                if let rate = summary.savedRateTenths, summary.saved > 0 {
                    Text("Bằng \(StatsPercentage.text(tenths: rate)) thu nhập của kỳ").font(.subheadline)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            HStack(spacing: Spacing.s) {
                StatTile(title: "Thu", value: MoneyFormatter.compact(report.income), icon: "arrow.up.circle",
                         trend: summary.comparison.flatMap { $0.income.isEmpty ? nil : $0.income.badgeText })
                StatTile(title: "Chi", value: MoneyFormatter.compact(report.expense), icon: "arrow.down.circle",
                         trend: summary.comparison.flatMap { $0.expense.isEmpty ? nil : $0.expense.badgeText })
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            if let label = summary.comparison?.label { Text(label.prefix(1).uppercased() + label.dropFirst()).font(.caption).foregroundStyle(.secondary) }
        }
        Section("Chi nhiều nhất") {
            if summary.topExpenses.isEmpty { Text("Không có khoản chi.").foregroundStyle(.secondary) }
            ForEach(Array(summary.topExpenses.enumerated()), id: \.offset) { index, row in
                LedgerRow(icon: row.icon, title: "\(index + 1). \(row.name)", subtitle: row.percentageText + " tổng chi",
                          amount: MoneyFormatter.compact(row.amount), progress: Double(row.percentageTenths) / 1_000,
                          tint: CategoryStyle.tint(for: row.icon), categoryIcon: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.name), \(spoken(row.amount)), \(row.percentageText) tổng chi")
            }
        }
        Section("Ngân sách") {
            if summary.budgets.isEmpty {
                Text("Kỳ này chưa đặt hạn mức.").foregroundStyle(.secondary)
            } else if summary.overBudget.isEmpty {
                Label("Giữ được trong tất cả hạn mức", systemImage: "checkmark.seal.fill").foregroundStyle(Color("Income"))
            } else {
                Label("Vượt \(summary.overBudget.count) hạn mức", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color("Expense"))
            }
            ForEach(summary.budgets, id: \.scope) { value in
                let name = BudgetPresentation.name(for: value.scope, categories: store.categories)
                LedgerRow(icon: value.scope == .total ? "target" : "tag", title: name,
                          subtitle: value.level == .over ? "Vượt \(MoneyFormatter.compact(-value.remaining))" : "Còn \(MoneyFormatter.compact(value.remaining))",
                          amount: MoneyFormatter.compact(value.spent) + " / " + MoneyFormatter.compact(value.limit),
                          progress: value.fraction, tint: value.level == .over ? Color("Expense") : value.level == .warning ? .orange : .accentColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BudgetPresentation.voiceOver(value, name: name))
            }
        }
        Section {
            NavigationLink { BudgetListView(store: store) } label: {
                IconRow(icon: "target", tint: .orange, title: "Đặt hạn mức cho kỳ mới")
            }
            if let onDone {
                Button("Xong", action: onDone).frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            Text("Mẹo: đặt hạn mức tổng để có số \"Hôm nay còn được tiêu\" trên app và widget.")
        }
    }
}

// MARK: - Installments and credit cards

struct InstallmentListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var adding = false
    @State private var editing: RecurringRule?

    var body: some View {
        let plans = store.installments
        List {
            if plans.isEmpty && store.creditCards.isEmpty {
                EmptyState(image: "illus-empty-budget", title: "Chưa có trả góp hay thẻ", message: "Thêm khoản trả góp để theo dõi số kỳ và số tiền còn lại",
                           symbol: "calendar.badge.clock", actionTitle: "Thêm trả góp") { adding = true }
            }
            let active = plans.filter { !$0.isFinished }, finished = plans.filter(\.isFinished)
            if !active.isEmpty {
                Section {
                    ForEach(active, id: \.ruleID) { plan in row(plan) }
                } header: { Text("Đang trả góp") } footer: {
                    let remaining = active.reduce(Int64(0)) { $0.addingReportingOverflow($1.remaining).partialValue }
                    Text("Còn phải trả tổng cộng \(MoneyFormatter.string(from: remaining)).")
                }
            }
            Section("Thẻ tín dụng") {
                if store.creditCards.isEmpty {
                    Text("Tạo ví loại \"Thẻ\" để theo dõi dư nợ, hạn mức và ngày đến hạn.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(store.creditCards, id: \.id) { card in
                    NavigationLink { WalletDetailView(store: store, wallet: card) } label: { cardRow(card) }
                }
            }
            if !finished.isEmpty {
                Section("Đã trả xong") { ForEach(finished, id: \.ruleID) { plan in row(plan) } }
            }
        }
        .navigationTitle("Trả góp & thẻ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Thêm trả góp")
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { InstallmentFormView(store: store) } }
        .sheet(item: $editing) { rule in NavigationStack { InstallmentFormView(store: store, rule: rule) } }
    }

    private func row(_ plan: InstallmentProgress) -> some View {
        Button { editing = store.recurringRules.first { $0.id == plan.ruleID } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.title).font(.headline)
                    if plan.isPaused { Text("Tạm dừng").font(.caption).padding(.horizontal, 6).background(.orange.opacity(0.2), in: Capsule()) }
                    Spacer()
                    Text(MoneyFormatter.compact(plan.perPeriod) + "/kỳ").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: plan.fraction).tint(plan.isFinished ? Color("Income") : .accentColor)
                HStack {
                    Text("Kỳ \(plan.paidPeriods)/\(plan.totalPeriods)").monospacedDigit()
                    Spacer()
                    Text(plan.isFinished ? "Đã trả \(MoneyFormatter.compact(plan.total))" : "Còn \(MoneyFormatter.compact(plan.remaining))").monospacedDigit()
                }.font(.caption)
                if let next = plan.nextDate, !plan.isFinished {
                    Text("Kỳ tới: \(TransactionPresentation.shortDate(next)) · kỳ cuối \(TransactionPresentation.shortDate(plan.endDate))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.title), đã trả \(plan.paidPeriods) trên \(plan.totalPeriods) kỳ, còn \(spoken(plan.remaining))")
        .accessibilityHint("Sửa khoản trả góp")
    }

    private func cardRow(_ card: Wallet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.name).font(.headline)
            if let status = store.cardStatus(card) {
                Text("Dư nợ \(MoneyFormatter.compact(status.debt))" + (status.available.map { " · còn hạn mức \(MoneyFormatter.compact($0))" } ?? ""))
                    .font(.subheadline).monospacedDigit()
                Text("Hạn \(TransactionPresentation.shortDate(status.dueDate)) · còn \(status.daysUntilDue) ngày")
                    .font(.caption).foregroundStyle(status.debt > 0 && status.daysUntilDue <= 3 ? Color("Expense") : .secondary)
            } else {
                Text("Chưa thiết lập ngày sao kê và hạn thanh toán").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct InstallmentFormView: View {
    @ObservedObject var store: TransactionScreenStore
    var rule: RecurringRule? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var perPeriod: Int64?
    @State private var periods = 12
    @State private var firstPayment = Date()
    @State private var walletID: UUID?
    @State private var categoryID: UUID?
    @State private var error: String?
    @State private var loaded = false

    private var wallets: [Wallet] { store.wallets.filter { $0.isOwn && (!$0.isArchived || $0.id == rule?.wallet?.id) } }
    private var categories: [Category] { store.categories.filter { $0.kindRaw == TransactionKind.expense.rawValue && (!$0.isArchived || $0.id == rule?.category?.id) } }
    private var end: Date? { InstallmentProgress.endDate(start: firstPayment, periods: periods) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && trimmedName.count <= 60 && perPeriod != nil && walletID != nil && end != nil }

    var body: some View {
        Form {
            Section {
                TextField("Tên, ví dụ: Trả góp iPhone", text: $name).frame(minHeight: 44)
                MoneyTextField(title: "Mỗi kỳ (₫)", amount: $perPeriod)
                Stepper("Số kỳ: \(periods)", value: $periods, in: 1...InstallmentProgress.maximumPeriods).frame(minHeight: 44)
                DatePicker("Ngày trả kỳ đầu", selection: $firstPayment, displayedComponents: .date).frame(minHeight: 44)
            } footer: {
                if let perPeriod, let end {
                    Text("Tổng \(MoneyFormatter.string(from: perPeriod.multipliedReportingOverflow(by: Int64(periods)).partialValue)) · trả ngày \(LocalCalendar.calendar.component(.day, from: firstPayment)) hằng tháng · kỳ cuối \(TransactionPresentation.shortDate(end))")
                }
            }
            Section("Trả từ") {
                Picker("Ví", selection: $walletID) {
                    Text("Chọn ví").tag(UUID?.none)
                    ForEach(wallets, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }.frame(minHeight: 44)
                Picker("Danh mục", selection: $categoryID) {
                    Text("Trả góp (tự tạo)").tag(UUID?.none)
                    ForEach(categories, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }.frame(minHeight: 44)
            }
            if let perPeriod, let walletID, let end {
                let draft = RecurringDraft(name: trimmedName, transaction: TransactionDraft(amount: perPeriod, kind: .expense, wallet: wallets.first { $0.id == walletID }),
                                           frequency: .monthly, interval: 1, startDate: firstPayment, endDate: end)
                let preview = RecurringPresentation.preview(draft, generatedThrough: rule?.generatedThrough)
                Section {
                    Text(preview.upcoming).font(.subheadline)
                    if let catchUp = preview.catchUp {
                        Callout(level: .warning, title: "Các kỳ đã qua sẽ được ghi ngay", message: catchUp + " Nếu đã trả vài kỳ trước khi dùng app, hãy chọn ngày kỳ tiếp theo và chỉ nhập số kỳ còn lại.")
                    }
                }
            }
            if let error { Section { InlineError(message: error) } }
            Section {
                Text("Mỗi kỳ được ghi thành một khoản chi định kỳ, có thể tạm dừng hoặc xóa trong Định kỳ.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(rule == nil ? "Thêm trả góp" : "Sửa trả góp")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) }
            ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save).disabled(!canSave).frame(minHeight: 44) }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        walletID = wallets.first { !$0.isArchived }?.id
        guard let rule else { return }
        name = rule.name; perPeriod = rule.amount; firstPayment = rule.startDate
        walletID = rule.wallet?.id; categoryID = rule.category?.id
        if let plan = InstallmentProgress.make(rule) { periods = plan.totalPeriods }
    }

    private func save() {
        guard let perPeriod else { return }
        do {
            try store.saveInstallment(name: trimmedName, perPeriod: perPeriod, periods: periods, firstPayment: firstPayment,
                                      wallet: wallets.first { $0.id == walletID }, category: categories.first { $0.id == categoryID }, editing: rule?.id)
            dismiss()
        } catch { self.error = TransactionPresentation.errorMessage(error) }
    }
}

/// Shown on a card wallet's detail screen.
struct CreditCardSection: View {
    @ObservedObject var store: TransactionScreenStore
    let wallet: Wallet
    @Binding var payingCard: Bool

    var body: some View {
        Section("Thẻ tín dụng") {
            if let status = store.cardStatus(wallet) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dư nợ").font(.subheadline).foregroundStyle(.secondary)
                            Text(MoneyFormatter.string(from: status.debt)).font(.title2.bold()).monospacedDigit()
                        }
                        Spacer()
                        if let available = status.available {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Còn hạn mức").font(.subheadline).foregroundStyle(.secondary)
                                Text(MoneyFormatter.compact(available)).font(.headline).monospacedDigit()
                                    .foregroundStyle(available < 0 ? Color("Expense") : .primary)
                            }
                        }
                    }
                    if let fraction = status.usedFraction {
                        ProgressView(value: fraction).tint(fraction >= 0.9 ? Color("Expense") : fraction >= 0.7 ? .orange : .accentColor)
                    }
                    Text("Kỳ sao kê \(StatsPeriod.dayMonth(status.periodStart))–\(StatsPeriod.dayMonth(status.statementDate)): đã chi \(MoneyFormatter.compact(status.spentThisPeriod))")
                        .font(.caption)
                    Label("Hạn thanh toán \(TransactionPresentation.shortDate(status.dueDate)) · còn \(status.daysUntilDue) ngày", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.debt > 0 && status.daysUntilDue <= 3 ? Color("Expense") : .secondary)
                }
                .accessibilityElement(children: .combine)
                if status.debt > 0 {
                    Button { payingCard = true } label: { IconRow(icon: "creditcard.and.123", tint: Color("Transfer"), title: "Thanh toán thẻ", value: MoneyFormatter.compact(status.debt)) }
                }
            } else {
                Text("Thiết lập hạn mức, ngày sao kê và hạn thanh toán để theo dõi dư nợ và nhận nhắc trước hạn.").font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink { CreditCardSettingsView(store: store, wallet: wallet) } label: {
                IconRow(icon: "gearshape", tint: .gray, title: store.cardStatus(wallet) == nil ? "Thiết lập thẻ tín dụng" : "Cài đặt thẻ")
            }
        }
    }
}

struct CreditCardSettingsView: View {
    @ObservedObject var store: TransactionScreenStore
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @State private var settings = CreditCardSettings()
    @State private var limit: Int64?
    @State private var hasSaved = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                MoneyTextField(title: "Hạn mức (₫)", amount: $limit, prompt: "Không bắt buộc")
                Picker("Ngày sao kê", selection: $settings.statementDay) { ForEach(1...31, id: \.self) { Text("Ngày \($0)").tag($0) } }.frame(minHeight: 44)
                Picker("Hạn thanh toán", selection: $settings.dueDay) { ForEach(1...31, id: \.self) { Text("Ngày \($0)").tag($0) } }.frame(minHeight: 44)
                Toggle("Nhắc trước hạn 3 ngày và đúng ngày", isOn: $settings.remindsBeforeDue).frame(minHeight: 44)
            } footer: {
                Text("Ngày lớn hơn số ngày của tháng sẽ lấy ngày cuối tháng. Hạn thanh toán nhỏ hơn hoặc bằng ngày sao kê được hiểu là ở tháng sau. Thiết lập này lưu trên máy, không nằm trong file sao lưu.")
            }
            Section {
                Text("Ghi chi tiêu bằng thẻ như khoản chi từ ví \(wallet.name). Khi trả thẻ, dùng Chuyển tiền từ ví ngân hàng sang ví thẻ.").font(.footnote).foregroundStyle(.secondary)
            }
            if hasSaved {
                Section { Button("Xóa thiết lập thẻ", role: .destructive) { store.saveCardSettings(nil, for: wallet.id); dismiss() }.frame(minHeight: 44) }
            }
        }
        .navigationTitle("Thẻ \(wallet.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") { settings.limit = limit; store.saveCardSettings(settings, for: wallet.id); dismiss() }.frame(minHeight: 44)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let saved = CreditCardSettingsStore.load(wallet.id) { settings = saved; limit = saved.limit; hasSaved = true }
        }
    }
}
