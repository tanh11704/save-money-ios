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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.m) {
                    if case .category(let id) = scope, let category = store.categories.first(where: { $0.id == id }) {
                        CategoryIcon(icon: category.icon, size: 44)
                    } else {
                        Image(systemName: "target").font(.title2).foregroundStyle(.tint).frame(width: 44, height: 44).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BudgetPresentation.name(for: scope, categories: store.categories)).font(.title3.weight(.semibold))
                        HStack(spacing: 4) {
                            Text("Từ tháng \(month.month)/\(String(month.year)) trở đi").font(.subheadline).foregroundStyle(.secondary)
                            InfoButton(text: "Áp dụng tháng này và các tháng sau. Các tháng trước giữ hạn mức cũ.")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Hạn mức mỗi tháng")
                    Card {
                        Button { keypadVisible.toggle() } label: {
                            HStack {
                                Text(MoneyFormatter.string(from: amount)).font(.system(.largeTitle, design: .rounded).bold())
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                                Spacer(minLength: 8)
                                Image(systemName: keypadVisible ? "keyboard.chevron.compact.down" : "keyboard").foregroundStyle(.tint).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("budget.amount").accessibilityHint("Ẩn hoặc hiện bàn phím số tiền")
                    }
                }
                if BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: store.budgetRules, replacing: scope, limit: amount) {
                    Callout(level: .warning, title: "Danh mục vượt hạn mức tổng", message: "Bạn vẫn có thể lưu các hạn mức độc lập.")
                }
                if BudgetService.activeRule(for: scope, in: month, rules: store.budgetRules) != nil {
                    Button(role: .destructive) { confirmingOff = true } label: {
                        Label("Tắt hạn mức", systemImage: "nosign").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }
                if let error { InlineError(message: error) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryActionBar(title: amount == 0 ? "Nhập hạn mức" : "Lưu hạn mức", enabled: valid, identifier: "budget.save", action: {
                do { try store.saveBudget(amount, scope: scope, month: month); dismiss() }
                catch { self.error = error.localizedDescription }
            }) {
                if keypadVisible { MoneyKeypad { amount = MoneyFormatter.applying($0, to: amount); error = nil } }
                // Only explain the range once the user has typed something out of it.
                if !valid && amount != 0 { InlineError(message: "Hạn mức phải trong 1…999.999.999.999 ₫") }
            }
        }
        .appSheet(.large)
        .navigationBarTitleDisplayMode(.inline)
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
