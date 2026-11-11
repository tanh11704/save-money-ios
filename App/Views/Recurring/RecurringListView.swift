import SwiftUI

@MainActor
struct RecurringListView: View {
    @ObservedObject var store: TransactionScreenStore
    @EnvironmentObject private var runtime: AppRuntime
    @State private var showingAdd = false
    @State private var editing: RecurringRule?
    @State private var expanded = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if !runtime.recurringIssues.isEmpty {
                Section("Cần xem lại") {
                    ForEach(runtime.recurringIssues, id: \.ruleID) { Text($0.reason).foregroundStyle(.secondary) }
                }
            }
            Section("Đang dùng") {
                if store.recurringRules.isEmpty { Text("Chưa có giao dịch định kỳ.").foregroundStyle(.secondary) }
                ForEach(store.recurringRules.filter { !$0.isPaused }, id: \.id) { rule in row(rule) }
            }
            DisclosureGroup("Đã tạm dừng (\(store.recurringRules.filter { $0.isPaused }.count))", isExpanded: $expanded) {
                ForEach(store.recurringRules.filter { $0.isPaused }, id: \.id) { rule in row(rule) }
            }.frame(minHeight: 44)
        }
        .navigationTitle("Giao dịch định kỳ")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button { showingAdd = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Thêm giao dịch định kỳ")
        } }
        .sheet(isPresented: $showingAdd) { NavigationStack { RecurringFormView(store: store) } }
        .sheet(item: $editing) { rule in NavigationStack { RecurringFormView(store: store, original: rule) } }
    }
    private func row(_ rule: RecurringRule) -> some View {
        Button { editing = rule } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.title).font(.headline)
                Text((rule.kindRaw == "expense" ? "−" : rule.kindRaw == "income" ? "+" : "") + MoneyFormatter.string(from: rule.amount)).monospacedDigit()
                Text(RecurringPresentation.schedule(rule)).font(.subheadline).foregroundStyle(.secondary)
                Text(RecurringPresentation.next(rule)).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .swipeActions(allowsFullSwipe: false) {
            Button(rule.isPaused ? "Tiếp tục" : "Tạm dừng") {
                do { try store.setRecurringPaused(!rule.isPaused, id: rule.id); error = nil }
                catch { self.error = error.localizedDescription }
            }.tint(.orange)
        }
        .accessibilityAction(named: Text(rule.isPaused ? "Tiếp tục" : "Tạm dừng")) {
            do { try store.setRecurringPaused(!rule.isPaused, id: rule.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}
