import SwiftUI

@MainActor
struct BudgetFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let scope: BudgetRule.Scope
    let month: ReportingMonth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var keypadVisible = true
    @State private var amount: Int64
    @State private var error: String?
    @State private var confirmingOff = false

    init(store: TransactionScreenStore, scope: BudgetRule.Scope, month: ReportingMonth) {
        self.store = store; self.scope = scope; self.month = month
        _amount = State(initialValue: BudgetService.activeRule(for: scope, in: month, rules: store.budgetRules)?.limit ?? 0)
    }
    private var valid: Bool { (1...MoneyFormatter.maximumInput).contains(amount) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(BudgetPresentation.name(for: scope, categories: store.categories)).font(.headline)
                Button { keypadVisible.toggle() } label: {
                    Text(MoneyFormatter.string(from: amount)).font(.largeTitle).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain).frame(minHeight: 44)
                    .accessibilityIdentifier("budget.amount").accessibilityHint("Ẩn hoặc hiện bàn phím số tiền")
                HStack { TrendBadge(delta: "Từ \(month.month)/\(String(month.year)) →"); InfoButton(text: "Áp dụng tháng này và các tháng sau. Các tháng trước giữ hạn mức cũ.") }
                if BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: store.budgetRules, replacing: scope, limit: amount) {
                    Callout(level: .warning, title: "Danh mục vượt hạn mức tổng", message: "Bạn vẫn có thể lưu các hạn mức độc lập.")
                }
                if BudgetService.activeRule(for: scope, in: month, rules: store.budgetRules) != nil {
                    Button("Tắt hạn mức", role: .destructive) { confirmingOff = true }.frame(minHeight: 44)
                }
                if let error { InlineError(message: error) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if keypadVisible { MoneyKeypad { amount = MoneyFormatter.applying($0, to: amount); error = nil } }
                Button {
                    do { try store.saveBudget(amount, scope: scope, month: month); dismiss() }
                    catch { self.error = error.localizedDescription }
                } label: { Text("Lưu").frame(maxWidth: .infinity, minHeight: 44) }
                    .appProminentButton().disabled(!valid)
                    .accessibilityIdentifier("budget.save")
                if !valid { InlineError(message: "Hạn mức phải trong 1…999.999.999.999 ₫") }
            }.padding().background(.bar)
        }
        .task { if typeSize.isAccessibilitySize { keypadVisible = false } }
        .navigationTitle("Đặt hạn mức")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .confirmationDialog("Tắt hạn mức từ tháng này?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Tắt hạn mức", role: .destructive) {
                do { try store.turnOffBudget(scope: scope, month: month); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("Các tháng trước giữ hạn mức cũ.") }
    }
}
