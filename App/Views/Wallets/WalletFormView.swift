import SwiftUI

@MainActor
struct WalletFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Wallet?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var keypadVisible = true
    @State private var name: String
    @State private var kind: WalletKind
    @State private var magnitude: Int64
    @State private var isDebt: Bool
    @State private var saveError: String?
    private enum Field: Hashable { case name }
    @FocusState private var focus: Field?

    init(store: TransactionScreenStore, original: Wallet? = nil) {
        self.store = store
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _kind = State(initialValue: WalletKind(rawValue: original?.kindRaw ?? "cash") ?? .cash)
        _magnitude = State(initialValue: WalletService.magnitude(of: original?.openingBalance ?? 0))
        _isDebt = State(initialValue: (original?.openingBalance ?? 0) < 0)
    }

    private func draft() throws -> WalletDraft {
        WalletDraft(name: name, kind: kind, openingBalance: try WalletService.openingBalance(magnitude: magnitude, isDebt: isDebt))
    }

    private var validationMessage: String? {
        do { try WalletService.validate(draft(), wallets: store.wallets, editing: original?.id); return nil }
        catch { return TransactionPresentation.errorMessage(error) }
    }

    private var nameMessage: String? {
        do {
            try WalletService.validate(WalletDraft(name: name, kind: kind), wallets: store.wallets, editing: original?.id)
            return nil
        } catch { return TransactionPresentation.errorMessage(error) }
    }

    private var amountMessage: String? {
        do { _ = try WalletService.openingBalance(magnitude: magnitude, isDebt: isDebt); return nil }
        catch { return TransactionPresentation.errorMessage(error) }
    }

    private static let kindOptions: [(value: WalletKind, title: String, icon: String)] =
        WalletKind.allCases.filter { $0 != .person && $0 != .adjustment }.map { ($0, $0.title, $0.icon) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // An empty name is the starting state, not an error worth showing in red.
                FormField(label: "Tên ví", text: $name, prompt: "Ví dụ: Tiền mặt, Vietcombank", error: name.isEmpty ? nil : nameMessage,
                          limit: 30, focus: $focus, field: .name, onSubmit: { focus = nil }, identifier: "wallet.name")
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Loại ví")
                    ChoiceChips(options: Self.kindOptions, selection: $kind)
                        .accessibilityIdentifier("wallet.kind")
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Số dư ban đầu")
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Button { focus = nil; keypadVisible.toggle() } label: {
                                HStack {
                                    Text(WalletService.displayOpening(magnitude: magnitude, isDebt: isDebt))
                                        .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                                        .foregroundStyle(isDebt && magnitude > 0 ? Color("Expense") : .primary)
                                        .lineLimit(1).minimumScaleFactor(0.4)
                                    Spacer(minLength: 8)
                                    Image(systemName: keypadVisible ? "keyboard.chevron.compact.down" : "keyboard")
                                        .foregroundStyle(.tint).accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Số dư ban đầu \(WalletService.displayOpening(magnitude: magnitude, isDebt: isDebt))".replacingOccurrences(of: "₫", with: "đồng"))
                                .accessibilityHint("Ẩn hoặc hiện bàn phím số tiền")
                            Divider()
                            Toggle(isOn: $isDebt) {
                                Label("Đang nợ (số dư âm)", systemImage: "minus.circle")
                            }.frame(minHeight: 44)
                        }
                    }
                    if let amountMessage { InlineError(message: amountMessage) }
                }
                openingBalanceWarning
                if let message = saveError {
                    InlineError(message: message)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                PrimaryActionBar(title: original == nil ? "Thêm ví" : "Lưu thay đổi", enabled: validationMessage == nil, action: save) {
                    if keypadVisible { MoneyKeypad { magnitude = MoneyFormatter.applying($0, to: magnitude); saveError = nil } }
                }
            }
        }
        .appSheet(.large)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton($focus)
        .task { if typeSize.isAccessibilitySize { keypadVisible = false } }
        .onChange(of: name) { _, _ in saveError = nil }
        .onChange(of: kind) { _, _ in saveError = nil }
        .onChange(of: isDebt) { _, _ in saveError = nil }
        .navigationTitle(original == nil ? "Thêm ví" : "Sửa ví")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
    }

    @ViewBuilder private var openingBalanceWarning: some View {
        if let original {
            if let input = try? draft(), input.openingBalance != original.openingBalance {
                if let preview = try? WalletService.preview(wallet: original, openingBalance: input.openingBalance, transactions: store.transactions) {
                    if preview.hasTransactions {
                        Callout(level: .warning, title: "Số dư hiện tại sẽ đổi",
                                message: "\(MoneyFormatter.string(from: preview.before)) → \(MoneyFormatter.string(from: preview.after))")
                    }
                } else { Text("Không thể tính số dư sau thay đổi. Hãy kiểm tra dữ liệu.").foregroundStyle(.red) }
            }
        }
    }

    private func save() {
        do { try store.saveWallet(draft(), editing: original?.id); dismiss() }
        catch { saveError = TransactionPresentation.errorMessage(error) }
    }
}
