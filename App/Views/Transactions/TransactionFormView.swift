import SwiftUI
import UIKit

@MainActor
struct TransactionFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Transaction?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expression: AmountExpression
    @State private var draft: TransactionDraft
    @State private var initialized = false
    @State private var showingDatePicker = false
    @State private var noteExpanded = false
    @State private var saveError: String?
    @State private var saved = false
    @State private var saving = false
    @State private var keypadVisible = true
    @FocusState private var noteFocused: Bool

    init(store: TransactionScreenStore, original: Transaction? = nil) {
        self.store = store
        self.original = original
        _expression = State(initialValue: AmountExpression(amount: original?.amount ?? 0))
        if let original {
            _draft = State(initialValue: TransactionDraft(amount: original.amount,
                kind: TransactionKind(rawValue: original.kindRaw) ?? .expense,
                date: original.date, note: original.note, wallet: original.wallet,
                toWallet: original.toWallet, category: original.category))
        } else { _draft = State(initialValue: TransactionDraft()) }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), alignment: .leading)]
    }

    private var validationMessage: String? {
        do { try TransactionValidator.validate(draft, editing: original); return nil }
        catch { return TransactionPresentation.errorMessage(error) }
    }

    private var visibleCategories: [Category] {
        let selection = store.recent.selection(for: draft.kind, wallets: store.wallets, categories: store.categories)
        return TransactionFormSelection.categories(store.categories, kind: draft.kind,
            retaining: original?.category?.id, recentID: selection.categoryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if original == nil && !store.wallets.contains(where: { !$0.isArchived }) {
                    Text("Chưa có ví đang dùng. Sang tab Ví để thêm hoặc khôi phục ví trước khi nhập giao dịch.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transaction.noActiveWallet")
                }
                kindPicker

                amountDisplay

                if draft.kind != .transfer {
                    categoryPicker
                }
                walletPicker(destination: false)
                if draft.kind == .transfer { walletPicker(destination: true) }
                dateSelection
                DisclosureGroup("Ghi chú", isExpanded: $noteExpanded) {
                    TextField("Ghi chú không bắt buộc", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($noteFocused)
                        .frame(minHeight: 44)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                        .accessibilityIdentifier("transaction.note")
                }
                .frame(minHeight: 44)
                if let message = store.errorMessage {
                    Text(message).foregroundStyle(.red)
                    Button("Tải lại dữ liệu") { reload() }
                        .frame(minHeight: 44)
                }
                Text("Chưa nhập dữ liệu thật trước khi hoàn tất sao lưu và khôi phục.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if noteFocused {
                Button("Xong ghi chú") { noteFocused = false }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .padding(8)
                    .background(.bar)
            } else { inputControls }
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            guard !initialized else { return }
            initialized = true
            if original == nil {
                draft = TransactionFormSelection.restoring(draft, wallets: store.wallets,
                    categories: store.categories, recent: store.recent)
            }
            noteExpanded = !draft.note.isEmpty
        }
        .onChange(of: draft.kind) { _, kind in
            draft = TransactionFormSelection.restoring(draft.changingKind(to: kind),
                wallets: store.wallets, categories: store.categories, recent: store.recent,
                preserveWallet: original != nil)
            saveError = nil
            saved = false
        }
        .onChange(of: store.snapshotVersion) { _, _ in
            draft = TransactionFormSelection.reconcile(draft, wallets: store.wallets,
                categories: store.categories, editing: original)
        }
        .task(id: saved) {
            guard saved else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { saved = false }
        }
        .navigationTitle(original == nil ? "Thêm giao dịch" : "Sửa giao dịch")
        .toolbar {
            if original != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
    }

    private var kindPicker: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // A system menu keeps the large labels readable on narrow iPhones.
                Picker("Loại giao dịch", selection: $draft.kind) { kindOptions }
                    .pickerStyle(.menu)
            } else {
                Picker("Loại giao dịch", selection: $draft.kind) { kindOptions }
                    .pickerStyle(.segmented)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("transaction.kind")
    }

    @ViewBuilder private var kindOptions: some View {
        Text("Chi").tag(TransactionKind.expense)
        Text("Thu").tag(TransactionKind.income)
        Text("Chuyển").tag(TransactionKind.transfer)
    }

    private var amountDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Số tiền").font(.headline)
            if expression.hasOperator {
                Text(expression.displayText).font(.title3).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Button { setKeypad(visible: true) } label: {
                HStack {
                    Text((expression.hasOperator && draft.amount >= 0 ? "= " : "") + MoneyFormatter.string(from: draft.amount))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.25)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !keypadVisible {
                        Image(systemName: "keyboard").foregroundStyle(.tint).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(TransactionPresentation.kindTitle(draft.kind)), \(expression.hasOperator ? expression.displayText.replacingOccurrences(of: "+", with: "cộng").replacingOccurrences(of: "−", with: "trừ") + ", bằng " : "số tiền ")\(MoneyFormatter.string(from: draft.amount).replacingOccurrences(of: "₫", with: "đồng"))")
            .accessibilityHint(keypadVisible ? "" : "Mở bàn phím số")
            .accessibilityIdentifier("transaction.amount")
            Text(keypadVisible ? "Tối đa 999.999.999.999 ₫" : "Chạm vào số tiền để mở bàn phím")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danh mục").font(.headline)
            if visibleCategories.isEmpty {
                Text("Không có danh mục phù hợp để chọn.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading) {
                ForEach(visibleCategories, id: \.id) { category in
                    SelectionChip(title: category.name + (category.isArchived ? " (đã lưu trữ)" : ""),
                                  icon: category.icon, selected: draft.category?.id == category.id) {
                        draft.category = category
                        saveError = nil
                        setKeypad(visible: false)
                    }
                }
            }
        }
    }

    private func walletPicker(destination: Bool) -> some View {
        let originalID = destination ? original?.toWallet?.id : original?.wallet?.id
        let wallets = TransactionFormSelection.wallets(store.wallets, retaining: originalID,
            excluding: destination ? draft.wallet?.id : nil)
        return VStack(alignment: .leading, spacing: 8) {
            Text(destination ? "Đến ví" : draft.kind == .transfer ? "Từ ví" : "Ví").font(.headline)
            if wallets.isEmpty { Text("Không có ví phù hợp để chọn.").foregroundStyle(.secondary) }
            LazyVGrid(columns: columns, alignment: .leading) {
                ForEach(wallets, id: \.id) { wallet in
                    SelectionChip(title: wallet.name + (wallet.isArchived ? " (đã lưu trữ)" : ""),
                        subtitle: store.balances[wallet.id],
                        selected: (destination ? draft.toWallet?.id : draft.wallet?.id) == wallet.id) {
                        if destination { draft.toWallet = wallet }
                        else { draft = TransactionFormSelection.selectingWallet(wallet, in: draft, available: store.wallets) }
                        saveError = nil
                        setKeypad(visible: false)
                    }
                }
            }
        }
    }

    private var dateSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ngày: \(TransactionPresentation.shortDate(draft.date))").font(.headline)
            LazyVGrid(columns: columns) {
                SelectionChip(title: "Hôm nay", selected: LocalCalendar.calendar.isDate(draft.date, inSameDayAs: Date())) {
                    draft.date = Date()
                }
                SelectionChip(title: "Hôm qua", selected: LocalCalendar.calendar.isDate(draft.date, inSameDayAs: TransactionPresentation.yesterday())) {
                    draft.date = TransactionPresentation.yesterday()
                }
                SelectionChip(title: "Chọn ngày", selected: showingDatePicker) {
                    showingDatePicker.toggle()
                    if showingDatePicker { setKeypad(visible: false) }
                }
            }
            if showingDatePicker {
                DatePicker("Ngày giao dịch", selection: $draft.date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .frame(minHeight: 44)
            }
        }
    }

    private var inputControls: some View {
        VStack(spacing: 8) {
            if saved {
                Text("Đã lưu").foregroundStyle(.secondary)
                    .accessibilityIdentifier("transaction.saved")
            }
            if keypadVisible {
                HStack {
                    Spacer()
                    Button { setKeypad(visible: false) } label: {
                        Label("Ẩn bàn phím", systemImage: "keyboard.chevron.compact.down")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("keypad.hide")
                }
                MoneyKeypad(showsOperators: true) { key in
                    expression.apply(key)
                    draft.amount = expression.result ?? 0
                    saveError = nil
                    saved = false
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button(action: save) {
                Label(original == nil ? "Lưu" : "Lưu thay đổi", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(validationMessage != nil || saving)
            .accessibilityIdentifier("transaction.save")
            if let message = saveError ?? validationMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("transaction.validation")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try TransactionValidator.validate(draft, editing: original)
            try store.save(draft, editing: original?.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: "Đã lưu")
            if original != nil { dismiss() }
            else {
                expression = AmountExpression()
                draft.amount = 0
                saveError = nil
                saved = true
                setKeypad(visible: true)
            }
        } catch { saveError = TransactionPresentation.errorMessage(error) }
    }

    /// The custom keypad is tall; collapsing it frees the scroll area so lower chips stay reachable.
    private func setKeypad(visible: Bool) {
        guard keypadVisible != visible else { return }
        withAnimation(.easeOut(duration: 0.2)) { keypadVisible = visible }
    }

    private func reload() {
        do { try store.reload() }
        catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
