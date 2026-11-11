import SwiftUI

@MainActor
struct BudgetListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var month = ReportingMonth()
    @State private var selection: Selection?
    private struct Selection: Identifiable {
        let id: BudgetRule.Scope
    }
    var body: some View {
        List {
            if store.budgetRules.isEmpty { EmptyState(image: "illus-empty-budget", title: "Chưa đặt hạn mức", message: "Đặt hạn mức để kiểm soát chi tiêu", symbol: "target", actionTitle: "Đặt hạn mức tổng") { selection = Selection(id: .total) } }
            Section("Hạn mức tổng tháng này") { row(scope: .total, title: "Hạn mức tổng", icon: "chart.bar") }
            Section("Danh mục chi") {
                ForEach(store.categories.filter { !$0.isArchived && $0.kindRaw == TransactionKind.expense.rawValue }, id: \.id) { category in
                    row(scope: .category(category.id), title: category.name, icon: category.icon)
                }
            }
            if let error = store.budgetError(in: month) { Callout(level: .danger, title: "Chưa tính được ngân sách", message: error) }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Ngân sách")
        .onAppear { month = ReportingMonth() }
        .sheet(item: $selection) { selected in
            NavigationStack { BudgetFormView(store: store, scope: selected.id, month: month) }
        }
    }
    private func row(scope: BudgetRule.Scope, title: String, icon: String) -> some View {
        Button { selection = Selection(id: scope) } label: {
            if let progress = store.progress(in: month).first(where: { $0.scope == scope }) {
                LedgerRow(icon: icon, title: title,
                          subtitle: progress.level == .over ? "Đã vượt · " + BudgetPresentation.remainingCompact(progress) : progress.level == .warning ? "Sắp hết · " + BudgetPresentation.remainingCompact(progress) : BudgetPresentation.remainingCompact(progress),
                          amount: MoneyFormatter.compact(progress.spent) + " / " + MoneyFormatter.compact(progress.limit),
                          progress: progress.fraction,
                          tint: progress.level == .over ? .red : progress.level == .warning ? .orange : .accentColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BudgetPresentation.voiceOver(progress, name: title))
                    .accessibilityValue(Text(progress.fraction, format: .percent.precision(.fractionLength(0))))
            } else {
                LedgerRow(icon: icon, title: title, amount: "+ Đặt")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
