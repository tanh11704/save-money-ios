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
            Section("Hạn mức tổng tháng này") { row(scope: .total, title: "Hạn mức tổng", icon: "chart.bar") }
            Section("Danh mục chi") {
                ForEach(store.categories.filter { !$0.isArchived && $0.kindRaw == TransactionKind.expense.rawValue }, id: \.id) { category in
                    row(scope: .category(category.id), title: category.name, icon: category.icon)
                }
            }
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
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                Text(BudgetService.activeRule(for: scope, in: month, rules: store.budgetRules)
                    .map { MoneyFormatter.string(from: $0.limit) } ?? "Chưa đặt")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
