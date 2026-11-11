import SwiftUI

@MainActor
struct TransferSheet: View {
    @ObservedObject var store: TransactionScreenStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: TransactionDraft
    @State private var expression = AmountExpression()
    @State private var error: String?
    @State private var saved = false
    private enum Field: Hashable { case note }
    @FocusState private var focus: Field?
    init(store: TransactionScreenStore, source: Wallet? = nil) {
        self.store = store
        var draft = TransactionFormSelection.restoring(TransactionDraft(kind: .transfer), wallets: store.wallets, categories: store.categories, recent: store.recent)
        if let source { draft = TransactionFormSelection.selectingWallet(source, in: draft, available: store.wallets) }
        _draft = State(initialValue: draft)
    }
    private var validation: String? {
        do { try TransactionValidator.validate(draft); _ = try preview(); return nil }
        catch { return error.localizedDescription }
    }
    private func preview() throws -> TransferPreview {
        guard let source = draft.wallet, let destination = draft.toWallet else { throw TransferPreview.PreviewError.invalidSelection }
        return try TransferPreview.make(amount: draft.amount, source: source, destination: destination, balances: store.balanceValues)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                walletPicker(destination: false)
                Button { let wallet = draft.wallet; draft.wallet = draft.toWallet; draft.toWallet = wallet } label: { Label("Đổi chiều", systemImage: "arrow.up.arrow.down").frame(minHeight: 44) }
                    .accessibilityLabel("Đổi ví nguồn và ví đích")
                walletPicker(destination: true)
                Card { VStack(alignment: .leading, spacing: 8) {
                    if expression.hasOperator { Text(expression.displayText).font(.title3).monospacedDigit() }
                    AmountText(amount: draft.amount, style: .system(.largeTitle, design: .rounded).bold())
                    if let source = draft.wallet, let balance = store.balanceValues[source.id], balance > 0, balance <= MoneyFormatter.maximumInput {
                        Button("Tất cả") { expression = AmountExpression(amount: balance); draft.amount = balance }.frame(minHeight: 44)
                    }
                } }
                if let preview = try? preview() {
                    Card { VStack(alignment: .leading, spacing: 12) {
                        Text("Xem trước").font(.headline)
                        Text(draft.wallet?.name ?? "Từ ví"); AmountText(amount: preview.sourceBefore); Image(systemName: "arrow.down").accessibilityHidden(true); AmountText(amount: preview.sourceAfter)
                        Divider()
                        Text(draft.toWallet?.name ?? "Đến ví"); AmountText(amount: preview.destinationBefore); Image(systemName: "arrow.down").accessibilityHidden(true); AmountText(amount: preview.destinationAfter)
                    } }
                    if preview.sourceGoesNegative { Callout(level: .warning, title: "Ví nguồn sẽ âm", message: MoneyFormatter.string(from: preview.sourceAfter)) }
                }
                HStack { Button("Hôm nay") { draft.date = Date() }; Button("Hôm qua") { draft.date = TransactionPresentation.yesterday() } }.buttonStyle(.bordered).frame(minHeight: 44)
                DatePicker("Ngày chuyển", selection: $draft.date, displayedComponents: .date).frame(minHeight: 44)
                TextField("Ghi chú", text: $draft.note, axis: .vertical).focused($focus, equals: .note).textFieldStyle(.roundedBorder).frame(minHeight: 44)
            }.padding()
        }
        .scrollDismissesKeyboard(.interactively).keyboardDoneButton($focus)
        .safeAreaInset(edge: .bottom) {
            if focus == nil {
                VStack(spacing: 8) {
                    if !typeSize.isAccessibilitySize { MoneyKeypad(showsOperators: true) { expression.apply($0); draft.amount = expression.result ?? 0 } }
                    else { DisclosureGroup("Bàn phím số") { MoneyKeypad(showsOperators: true) { expression.apply($0); draft.amount = expression.result ?? 0 } } }
                    Button("Chuyển", action: save).buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(validation != nil || saved)
                    if let message = error ?? validation { Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                }.padding(8).background(.bar)
            }
        }
        .navigationTitle("Chuyển tiền")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .sensoryFeedback(.success, trigger: saved) { _, _ in !reduceMotion }
        .overlay(alignment: .top) { if saved { Toast(message: "Đã chuyển \(MoneyFormatter.string(from: draft.amount)) · \(draft.wallet?.name ?? "") → \(draft.toWallet?.name ?? "")") } }
        .task(id: saved) { if saved { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { dismiss() } } }
    }
    private func walletPicker(destination: Bool) -> some View {
        Picker(destination ? "Đến" : "Từ", selection: destination ? $draft.toWallet : $draft.wallet) {
            Text("Chọn ví").tag(Optional<Wallet>.none)
            ForEach(store.wallets.filter { !$0.isArchived && $0.id != (destination ? draft.wallet?.id : draft.toWallet?.id) }, id: \.id) { wallet in
                Text(wallet.name).tag(Optional(wallet))
            }
        }.pickerStyle(.menu).frame(minHeight: 44)
    }
    private func save() {
        guard !saved else { return }
        do { try TransactionValidator.validate(draft); _ = try preview(); try store.save(draft, editing: nil); saved = true }
        catch { self.error = error.localizedDescription }
    }
}
