import SwiftUI

@MainActor
struct TransferSheet: View {
    enum Mode { case transfer; case debt(person: Wallet, action: DebtPresentation.Action) }
    let mode: Mode
    @ObservedObject var store: TransactionScreenStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: TransactionDraft
    @State private var expression = AmountExpression()
    @State private var error: String?
    @State private var saved = false
    /// Fee charged by the source (e.g. ATM withdrawal); recorded as a separate expense. Defaults to 0 ₫.
    @State private var fee: Int64 = 0
    @State private var feeExpression = AmountExpression()
    private enum KeypadTarget { case amount, fee }
    @State private var keypadTarget = KeypadTarget.amount
    private enum Field: Hashable { case note }
    @FocusState private var focus: Field?
    init(store: TransactionScreenStore, source: Wallet? = nil, mode: Mode = .transfer, amount: Int64 = 0) {
        self.store = store
        self.mode = mode
        let wallets = store.wallets.filter { $0.isOwn }
        var draft = TransactionFormSelection.restoring(TransactionDraft(kind: .transfer), wallets: wallets, categories: store.categories, recent: store.recent)
        if let source, source.isOwn { draft = TransactionFormSelection.selectingWallet(source, in: draft, available: wallets) }
        if case .debt(let person, let action) = mode {
            let own = draft.wallet ?? wallets.first { !$0.isArchived }
            draft.wallet = action == .lend || action == .repay ? own : person
            draft.toWallet = action == .lend || action == .repay ? person : own
        }
        draft.amount = amount
        _expression = State(initialValue: AmountExpression(amount: amount))
        _draft = State(initialValue: draft)
    }
    private var person: Wallet? { if case .debt(let person, _) = mode { return person }; return nil }
    private var action: DebtPresentation.Action? { if case .debt(_, let action) = mode { return action }; return nil }
    private var title: String { if let person, let action { return DebtPresentation.title(action, person: person) }; return "Chuyển tiền" }
    private var quickAmount: Int64? {
        if let person, action == .collect || action == .repay { return store.balanceValues[person.id].flatMap { Int64(exactly: $0.magnitude) } }
        guard person == nil, let source = draft.wallet else { return nil }
        return store.balanceValues[source.id]
    }
    /// Fees only apply between the user's own wallets, never to debt payments.
    private var effectiveFee: Int64 { person == nil ? fee : 0 }
    private func applyKey(_ key: MoneyFormatter.Key) {
        switch keypadTarget {
        case .amount: expression.apply(key); draft.amount = expression.result ?? 0
        case .fee: feeExpression.apply(key); fee = feeExpression.result ?? 0
        }
        error = nil
    }
    private var validation: String? {
        do { try TransactionValidator.validate(draft); _ = try preview(); return nil }
        catch { return error.localizedDescription }
    }
    private func preview() throws -> TransferPreview {
        guard let source = draft.wallet, let destination = draft.toWallet else { throw TransferPreview.PreviewError.invalidSelection }
        return try TransferPreview.make(amount: draft.amount, fee: effectiveFee, source: source, destination: destination, balances: store.balanceValues)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                walletPicker(destination: false)
                if person == nil {
                    Button { let wallet = draft.wallet; draft.wallet = draft.toWallet; draft.toWallet = wallet } label: { Label("Đổi chiều", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                        .accessibilityLabel("Đổi ví nguồn và ví đích")
                }
                walletPicker(destination: true)
                Card { VStack(alignment: .leading, spacing: 8) {
                    if person == nil { Text("Số tiền chuyển").font(.subheadline).foregroundStyle(.secondary) }
                    if expression.hasOperator { Text(expression.displayText).font(.title3).monospacedDigit() }
                    AmountText(amount: draft.amount, style: .system(.largeTitle, design: .rounded).bold())
                    if let amount = quickAmount, amount > 0 {
                        Button(person == nil ? "Tất cả" : action == .collect ? "Thu hết" : "Trả hết") {
                            guard amount <= MoneyFormatter.maximumInput else { error = "Số tiền vượt 999.999.999.999 đồng. Chuyển thành nhiều lần."; return }
                            expression = AmountExpression(amount: amount); draft.amount = amount; error = nil
                        }.frame(minHeight: 44)
                    }
                } }
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: person == nil && keypadTarget == .amount ? 2 : 0))
                .contentShape(Rectangle())
                .onTapGesture { keypadTarget = .amount; focus = nil }
                .accessibilityAddTraits(person == nil && keypadTarget == .amount ? .isSelected : [])
                if person == nil { feeCard }
                if let preview = try? preview() {
                    Card { VStack(alignment: .leading, spacing: 12) {
                        Text("Xem trước").font(.headline)
                        Text(draft.wallet?.name ?? "Từ ví"); AmountText(amount: preview.sourceBefore); Image(systemName: "arrow.down").accessibilityHidden(true); AmountText(amount: preview.sourceAfter)
                        if effectiveFee > 0 { Text("Gồm phí \(MoneyFormatter.string(from: effectiveFee)), ghi thành khoản chi \"\(TransactionService.transferFeeCategoryName)\"").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        Text(draft.toWallet?.name ?? "Đến ví"); AmountText(amount: preview.destinationBefore); Image(systemName: "arrow.down").accessibilityHidden(true); AmountText(amount: preview.destinationAfter)
                    } }
                    if let person {
                        let before = draft.wallet?.id == person.id ? preview.sourceBefore : preview.destinationBefore
                        let after = draft.wallet?.id == person.id ? preview.sourceAfter : preview.destinationAfter
                        Text(DebtPresentation.balanceText(after, person: person)).font(.headline)
                        if (before > 0 && after < 0) || (before < 0 && after > 0) {
                            Callout(level: .warning, title: "Số tiền vượt số còn nợ", message: DebtPresentation.balanceText(after, person: person))
                        }
                    }
                    if preview.sourceGoesNegative && draft.wallet?.isOwn == true { Callout(level: .warning, title: "Ví nguồn sẽ âm", message: MoneyFormatter.string(from: preview.sourceAfter)) }
                }
                HStack { Button("Hôm nay") { draft.date = Date() }; Button("Hôm qua") { draft.date = TransactionPresentation.yesterday() } }.buttonStyle(.bordered).frame(minHeight: 44)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Ngày chuyển")
                    DatePicker("Ngày chuyển", selection: $draft.date, displayedComponents: .date).labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(minHeight: 44)
                }
                FormField(label: "Ghi chú", text: $draft.note, prompt: "Không bắt buộc", multiline: true,
                          submitLabel: .return, focus: $focus, field: .note, identifier: "transfer.note")
            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).padding()
        }
        .scrollDismissesKeyboard(.interactively).keyboardDoneButton($focus)
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                PrimaryActionBar(title: draft.amount == 0 ? "Nhập số tiền" : title, systemImage: draft.amount == 0 ? "keyboard" : "arrow.left.arrow.right",
                                 enabled: validation == nil && !saved, identifier: "transfer.save", action: save) {
                    if person == nil { Text(keypadTarget == .fee ? "Đang nhập phí chuyển" : "Đang nhập số tiền chuyển").font(.caption).foregroundStyle(.secondary) }
                    if !typeSize.isAccessibilitySize { MoneyKeypad(showsOperators: true) { applyKey($0) } }
                    else { DisclosureGroup("Bàn phím số") { MoneyKeypad(showsOperators: true) { applyKey($0) } } }
                    // A zero amount is the starting state; only explain other problems.
                    if let message = error ?? (draft.amount == 0 ? nil : validation) { InlineError(message: message) }
                }
            }
        }
        .appSheet(.large)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(title)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .sensoryFeedback(.success, trigger: saved) { _, _ in !reduceMotion }
        .overlay(alignment: .top) { if saved { Toast(message: "Đã lưu \(MoneyFormatter.string(from: draft.amount)) · \(draft.wallet?.name ?? "") → \(draft.toWallet?.name ?? "")" + (effectiveFee > 0 ? " · phí \(MoneyFormatter.string(from: effectiveFee))" : "")) } }
        .task(id: saved) { if saved { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { dismiss() } } }
    }
    private var feeCard: some View {
        Card { HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phí chuyển").font(.subheadline).foregroundStyle(.secondary)
                if feeExpression.hasOperator { Text(feeExpression.displayText).font(.caption).monospacedDigit() }
                AmountText(amount: fee, style: .title3.bold())
                Text("Ví dụ phí rút ATM. Trừ thêm vào ví nguồn, tính là khoản chi.").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if fee > 0 {
                Button { fee = 0; feeExpression = AmountExpression() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Bỏ phí chuyển")
            }
        } }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: keypadTarget == .fee ? 2 : 0))
        .contentShape(Rectangle())
        .onTapGesture { keypadTarget = .fee; focus = nil }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Phí chuyển, \(MoneyFormatter.string(from: fee).replacingOccurrences(of: "₫", with: "đồng"))")
        .accessibilityHint("Chạm để nhập phí bằng bàn phím số")
        .accessibilityAddTraits(keypadTarget == .fee ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { keypadTarget = .fee }
        .accessibilityIdentifier("transfer.fee")
    }
    @ViewBuilder private func walletPicker(destination: Bool) -> some View {
        let selected = destination ? draft.toWallet : draft.wallet
        if let person, selected?.id == person.id {
            WalletCard(wallet: person, balance: store.balanceValues[person.id])
        } else {
        Menu {
            ForEach(store.wallets.filter { $0.isOwn && !$0.isArchived && $0.id != (destination ? draft.wallet?.id : draft.toWallet?.id) }, id: \.id) { wallet in
                Button(wallet.name) { if destination { draft.toWallet = wallet } else { draft.wallet = wallet }; error = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(destination ? "Đến" : "Từ").font(.subheadline).foregroundStyle(Color.secondary)
                HStack(alignment: .top) {
                    Text(selected?.name ?? "Chọn ví").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                }
            }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }
    private func save() {
        guard !saved else { return }
        do { try TransactionValidator.validate(draft); _ = try preview(); try store.saveTransfer(draft, fee: effectiveFee); saved = true }
        catch { self.error = error.localizedDescription }
    }
}
