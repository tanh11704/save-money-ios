import SwiftUI
import UIKit

@MainActor
struct TransactionFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Transaction?
    private let prefillWallet: Wallet?
    var onNeedsWallet: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expression: AmountExpression
    @State private var draft: TransactionDraft
    @State private var routedPrefillNeedsSelection = false
    @State private var skipKindRestoration = false
    @State private var initialized = false
    @State private var showingDatePicker = false
    @State private var noteExpanded = false
    @State private var saveError: String?
    @State private var saved = false
    @State private var savedMessage = ""
    @State private var saveTrigger = 0
    @State private var selectionTrigger = 0
    @State private var saving = false
    @State private var keypadVisible = true
    private enum Field: Hashable { case note }
    @FocusState private var focus: Field?

    init(store: TransactionScreenStore, original: Transaction? = nil, onNeedsWallet: (() -> Void)? = nil, prefillKind: TransactionKind? = nil, prefillWallet: Wallet? = nil, prefillAmount: Int64 = 0) {
        self.store = store
        self.original = original
        self.prefillWallet = prefillWallet
        self.onNeedsWallet = onNeedsWallet
        _expression = State(initialValue: AmountExpression(amount: original?.amount ?? prefillAmount))
        if let original {
            _draft = State(initialValue: TransactionDraft(amount: original.amount,
                kind: TransactionKind(rawValue: original.kindRaw) ?? .expense,
                date: original.date, note: original.note, wallet: original.wallet,
                toWallet: original.toWallet, category: original.category))
        } else { _draft = State(initialValue: TransactionDraft(amount: prefillAmount, kind: prefillKind ?? .expense, wallet: prefillWallet)) }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), alignment: .leading)]
    }

    private var validationError: TransactionValidator.ValidationError? {
        TransactionValidator.validationErrors(draft, editing: original).first
    }

    private var validationMessage: String? {
        validationError.map { TransactionPresentation.errorMessage($0) }
    }

    private var inlineMessage: String? {
        if let saveError { return saveError }
        return TransactionValidator.validationErrors(draft, editing: original)
            .first { TransactionPresentation.showsInlineError($0, amount: draft.amount) }
            .map { TransactionPresentation.errorMessage($0) }
    }

    private var saveTitle: String {
        if validationError == nil && original != nil { return "Lưu thay đổi" }
        return TransactionPresentation.saveButtonTitle(for: validationError)
    }

    private var visibleCategories: [Category] {
        let selection = store.recent.selection(for: draft.kind, wallets: store.wallets, categories: store.categories)
        return TransactionFormSelection.categories(store.categories, kind: draft.kind,
            retaining: original?.category?.id, recentID: selection.categoryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if original == nil && !store.wallets.contains(where: { !$0.isArchived && !$0.isPerson }) {
                    EmptyState(image: "illus-empty-wallet", title: "Chưa có ví", message: "Thêm ví để ghi giao dịch", symbol: "wallet.bifold", actionTitle: "Thêm ví", action: onNeedsWallet)
                        .accessibilityIdentifier("transaction.noActiveWallet")
                }
                if !keypadVisible, let message = inlineMessage {
                    InlineError(message: message).accessibilityIdentifier("transaction.validation")
                }
                amountDisplay

                if draft.kind != .transfer {
                    categoryPicker
                }
                walletPicker(destination: false)
                if draft.kind == .transfer { walletPicker(destination: true) }
                dateSelection
                DisclosureGroup(isExpanded: $noteExpanded) {
                    TextField("Ghi chú không bắt buộc", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .note)
                        .frame(minHeight: 44)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                        .accessibilityIdentifier("transaction.note")
                } label: { IconRow(icon: "text.alignleft", title: noteExpanded || !draft.note.isEmpty ? "Ghi chú" : "Thêm ghi chú") }
                .frame(minHeight: 44)
                if let message = store.errorMessage {
                    Text(message).foregroundStyle(.red)
                    Button("Tải lại dữ liệu") { reload() }
                        .frame(minHeight: 44)
                }
            }
            .padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil { inputControls }
        }
        .tint(Color(draft.kind == .income ? "Income" : draft.kind == .expense ? "Expense" : "Transfer"))
        .sensoryFeedback(.success, trigger: saveTrigger) { _, _ in !reduceMotion }
        .sensoryFeedback(.selection, trigger: selectionTrigger) { _, _ in !reduceMotion }
        .overlay(alignment: .top) { if saved { Toast(message: savedMessage).accessibilityIdentifier("transaction.saved") } }
        .keyboardDoneButton($focus)
        .scrollDismissesKeyboard(.interactively)
        .task {
            guard !initialized else { return }
            initialized = true
            if typeSize.isAccessibilitySize { keypadVisible = false }
            if original == nil {
                draft = TransactionFormSelection.restoring(draft, wallets: store.wallets.filter { !$0.isPerson },
                    categories: store.categories, recent: store.recent)
            }
            if let prefillWallet { draft.wallet = prefillWallet }
            if routedPrefillNeedsSelection { draft.category = nil; draft.toWallet = nil }
            noteExpanded = !draft.note.isEmpty
        }
        .onChange(of: store.addPrefill?.id, initial: true) { _, _ in
            guard original == nil, let prefill = store.addPrefill else { return }
            if let kind = prefill.kind {
                skipKindRestoration = kind != draft.kind
                draft = TransactionFormSelection.restoring(draft.changingKind(to: kind), wallets: store.wallets.filter { !$0.isPerson }, categories: store.categories, recent: store.recent)
            }
            if let amount = prefill.amount { expression = AmountExpression(amount: amount); draft.amount = amount }
            routedPrefillNeedsSelection = true
            draft.category = nil; draft.toWallet = nil
            saveError = nil; saved = false; store.addPrefill = nil
        }
        .onChange(of: draft.kind) { _, kind in
            if skipKindRestoration { skipKindRestoration = false; return }
            draft = TransactionFormSelection.restoring(draft.changingKind(to: kind),
                wallets: store.wallets.filter { !$0.isPerson }, categories: store.categories, recent: store.recent,
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { kindPicker.frame(maxWidth: 320) }
            if original != nil || prefillWallet != nil {
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
        Label("Chi", systemImage: "arrow.down.circle").tag(TransactionKind.expense)
        Label("Thu", systemImage: "arrow.up.circle").tag(TransactionKind.income)
        Label("Chuyển", systemImage: "arrow.left.arrow.right.circle").tag(TransactionKind.transfer)
    }

    private var amountDisplay: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Text("Số tiền").font(.headline)
            if expression.hasOperator {
                Text(expression.displayText).font(.title3).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Button { setKeypad(visible: true) } label: {
                HStack {
                    AmountText(amount: draft.amount, style: .system(.largeTitle, design: .rounded).bold(), prefix: expression.hasOperator && draft.amount >= 0 ? "= " : "")
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
        } }
    }

    private var categoryPicker: some View {
        let subtitles = draft.kind == .expense ? store.budgetSubtitles(on: draft.date) : [:]
        let compactSubtitles = draft.kind == .expense ? store.budgetSubtitles(on: draft.date, compact: true) : [:]
        let overBudget = draft.kind == .expense ? store.overBudgetCategories(on: draft.date) : []
        return VStack(alignment: .leading, spacing: 8) {
            Text("Danh mục").font(.headline)
            if visibleCategories.isEmpty {
                Text("Không có danh mục phù hợp để chọn.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading) {
                ForEach(visibleCategories, id: \.id) { category in
                    let selected = draft.category?.id == category.id
                    Button {
                        draft.category = category
                        selectionTrigger += 1
                        saveError = nil
                        setKeypad(visible: false)
                    } label: {
                        VStack(spacing: 6) {
                            CategoryIcon(icon: category.icon, size: 48)
                                .overlay(alignment: .topTrailing) { if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color("OnAccent"), Color.accentColor).accessibilityHidden(true) } }
                            Text(category.name).font(.caption).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            if let subtitle = (typeSize.isAccessibilitySize ? subtitles : compactSubtitles)[category.id] {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    if overBudget.contains(category.id) { Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true) }
                                    Text(subtitle).monospacedDigit()
                                }.font(.caption2)
                                    .foregroundStyle(overBudget.contains(category.id) ? Color("Expense") : Color.secondary)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 92, alignment: .top).padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                    .accessibilityLabel([category.name, subtitles[category.id]].compactMap { $0 }.joined(separator: ", ").replacingOccurrences(of: "₫", with: "đồng"))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("transaction.category.\(category.id)")
                }
            }
        }
    }

    private func walletPicker(destination: Bool) -> some View {
        let originalID = destination ? original?.toWallet?.id : original?.wallet?.id
        let wallets = TransactionFormSelection.wallets(store.wallets.filter { !$0.isPerson || $0.id == originalID }, retaining: originalID,
            excluding: destination ? draft.wallet?.id : nil)
        return VStack(alignment: .leading, spacing: 8) {
            Text(destination ? "Đến ví" : draft.kind == .transfer ? "Từ ví" : "Ví").font(.headline)
            if wallets.isEmpty { Text("Không có ví phù hợp để chọn.").foregroundStyle(.secondary) }
            Group {
                if typeSize.isAccessibilitySize { VStack { walletChoices(wallets, destination: destination) } }
                else { ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 12) { walletChoices(wallets, destination: destination) } } }
            }
            if !destination && draft.kind == .expense {
                if let person = draft.wallet, person.isPerson { Label("\(person.name) trả hộ", systemImage: "person.crop.circle").font(.headline) }
                Menu("Người khác trả hộ…") {
                    ForEach(store.wallets.filter { $0.isPerson && !$0.isArchived }, id: \.id) { person in
                        Button(person.name) { draft.wallet = person; saveError = nil; setKeypad(visible: false) }
                    }
                }.frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder private func walletChoices(_ wallets: [Wallet], destination: Bool) -> some View {
        ForEach(wallets, id: \.id) { wallet in
            let selected = (destination ? draft.toWallet?.id : draft.wallet?.id) == wallet.id
            Button {
                if destination { draft.toWallet = wallet }
                else { draft = TransactionFormSelection.selectingWallet(wallet, in: draft, available: store.wallets.filter { !$0.isPerson }) }
                saveError = nil
                setKeypad(visible: false)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label(wallet.name, systemImage: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
                        .padding(.trailing, 22)
                    Text(store.balances[wallet.id] ?? "Chưa tính được")
                        .font(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
                }.padding(Spacing.m)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 168, height: typeSize.isAccessibilitySize ? nil : 84, alignment: .topLeading)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).padding(8).accessibilityHidden(true) }
                    }
            }.buttonStyle(.plain)
                .accessibilityLabel("\(wallet.name), \(store.balances[wallet.id] ?? "Chưa tính được số dư")".replacingOccurrences(of: "₫", with: "đồng"))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                SelectionChip(title: "Chọn", icon: "calendar", selected: showingDatePicker) {
                    showingDatePicker.toggle()
                    if showingDatePicker { setKeypad(visible: false) }
                }
            }
            if showingDatePicker {
                DatePicker("Ngày giao dịch", selection: $draft.date, displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(minHeight: 44)
            }
        }
    }

    private var inputControls: some View {
        VStack(spacing: 8) {
            if keypadVisible {
                HStack {
                    Spacer()
                    Button { setKeypad(visible: false) } label: {
                        Label(typeSize.isAccessibilitySize ? "Ẩn phím" : "Ẩn bàn phím", systemImage: "keyboard.chevron.compact.down")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Ẩn bàn phím")
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
                Label(saveTitle, systemImage: draft.amount == 0 ? "keyboard" : "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .appProminentButton()
            .disabled(validationMessage != nil || saving)
            .accessibilityLabel(saveTitle)
            .accessibilityHint(draft.amount == 0 ? "Mở bàn phím số" : "")
            .accessibilityAction(named: Text("Mở bàn phím số")) { focus = nil; setKeypad(visible: true) }
            .accessibilityIdentifier("transaction.save")
            .overlay {
                if draft.amount == 0 && !saving {
                    // The save action stays disabled; this separate hit area opens input.
                    Button { focus = nil; setKeypad(visible: true) } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityHidden(true)
                }
            }
            if keypadVisible, let message = inlineMessage {
                InlineError(message: message)
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
            savedMessage = "Đã lưu \((draft.kind == .expense ? "−" : draft.kind == .income ? "+" : "") + MoneyFormatter.string(from: draft.amount)) · \(draft.category?.name ?? "Chuyển tiền")"
            saveTrigger += 1
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
        if reduceMotion { keypadVisible = visible }
        else { withAnimation(.easeOut(duration: 0.2)) { keypadVisible = visible } }
    }

    private func reload() {
        do { try store.reload() }
        catch { store.errorMessage = TransactionPresentation.errorMessage(error) }
    }
}
