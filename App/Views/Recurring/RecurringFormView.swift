import SwiftUI

@MainActor
struct RecurringFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: RecurringRule?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: RecurringDraft
    @State private var expression: AmountExpression
    @State private var hasEnd: Bool
    @State private var error: String?
    @State private var keypadVisible = true
    init(store: TransactionScreenStore, original: RecurringRule? = nil) {
        self.store = store; self.original = original
        var initial = original?.draft ?? RecurringDraft()
        if original == nil {
            initial.transaction = TransactionFormSelection.restoring(initial.transaction, wallets: store.wallets, categories: store.categories, recent: store.recent)
        }
        _draft = State(initialValue: initial)
        _expression = State(initialValue: AmountExpression(amount: initial.transaction.amount))
        _hasEnd = State(initialValue: initial.endDate != nil)
    }
    private var transaction: Binding<TransactionDraft> { Binding(get: { draft.transaction }, set: { draft.transaction = $0 }) }
    private var validation: String? {
        do { try RecurringValidator.validate(draft); return nil }
        catch { return error.localizedDescription }
    }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140))] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Tên (không bắt buộc)", text: $draft.name).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                Picker("Loại", selection: transaction.kind) {
                    Text("Chi").tag(TransactionKind.expense); Text("Thu").tag(TransactionKind.income); Text("Chuyển").tag(TransactionKind.transfer)
                }.pickerStyle(.menu).frame(minHeight: 44)
                if expression.hasOperator { Text(expression.displayText).font(.title3).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Button { keypadVisible.toggle() } label: {
                    Text(MoneyFormatter.string(from: draft.transaction.amount)).font(.largeTitle).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityHint("Ẩn hoặc hiện bàn phím số tiền")
                if draft.transaction.kind != .transfer {
                    Text("Danh mục").font(.headline)
                    LazyVGrid(columns: columns) {
                        ForEach(store.categories.filter { !$0.isArchived && $0.kindRaw == draft.transaction.kind.rawValue }, id: \.id) { category in
                            SelectionChip(title: category.name, icon: category.icon, selected: draft.transaction.category?.id == category.id) {
                                draft.transaction.category = category; keypadVisible = false
                            }
                        }
                    }
                }
                wallets(destination: false)
                if draft.transaction.kind == .transfer { wallets(destination: true) }
                TextField("Ghi chú", text: transaction.note, axis: .vertical).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                Picker("Chu kỳ", selection: $draft.frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text("Hằng " + $0.title).tag($0) }
                }.frame(minHeight: 44)
                Stepper("Mỗi \(draft.interval) \(draft.frequency.title)", value: $draft.interval, in: 1...Int.max).frame(minHeight: 44)
                DatePicker("Ngày bắt đầu", selection: $draft.startDate, displayedComponents: .date).frame(minHeight: 44)
                Toggle("Có ngày kết thúc", isOn: $hasEnd).frame(minHeight: 44)
                if hasEnd {
                    DatePicker("Ngày kết thúc", selection: Binding(get: { draft.endDate ?? draft.startDate }, set: { draft.endDate = $0 }), displayedComponents: .date).frame(minHeight: 44)
                }
                let preview = RecurringPresentation.preview(draft, generatedThrough: original?.generatedThrough)
                Text(preview.upcoming).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if original?.isPaused == true { Text("Quy tắc đang tạm dừng. Chỉ sinh khi bạn bấm Tiếp tục.").font(.footnote) }
                else if let catchUp = preview.catchUp { Text(catchUp).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                if original != nil { Text("Thay đổi chỉ áp dụng cho các lần sau; giao dịch đã sinh giữ nguyên.").font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if keypadVisible {
                    Button("Ẩn bàn phím") { keypadVisible = false }.frame(minHeight: 44)
                    MoneyKeypad(showsOperators: true) { key in expression.apply(key); draft.transaction.amount = expression.result ?? 0 }
                }
                Button {
                    do { try store.saveRecurring(draft, editing: original?.id); dismiss() }
                    catch { self.error = error.localizedDescription }
                } label: { Text("Lưu").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).disabled(validation != nil)
                if let message = error ?? validation { Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding().background(.bar)
        }
        .navigationTitle(original == nil ? "Thêm định kỳ" : "Sửa định kỳ")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .onChange(of: hasEnd) { _, enabled in draft.endDate = enabled ? draft.startDate : nil }
        .onChange(of: draft.transaction.kind) { _, kind in
            draft.transaction = TransactionFormSelection.restoring(draft.transaction.changingKind(to: kind), wallets: store.wallets,
                categories: store.categories, recent: store.recent)
        }
    }
    private func wallets(destination: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(destination ? "Đến ví" : "Ví").font(.headline)
            LazyVGrid(columns: columns) {
                ForEach(store.wallets.filter { !$0.isArchived && (!destination || $0.id != draft.transaction.wallet?.id) }, id: \.id) { wallet in
                    SelectionChip(title: wallet.name, selected: (destination ? draft.transaction.toWallet?.id : draft.transaction.wallet?.id) == wallet.id) {
                        if destination { draft.transaction.toWallet = wallet }
                        else { draft.transaction = TransactionFormSelection.selectingWallet(wallet, in: draft.transaction, available: store.wallets) }
                        keypadVisible = false
                    }
                }
            }
        }
    }
}
