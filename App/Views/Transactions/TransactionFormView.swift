import SwiftUI
import UIKit

@MainActor
struct TransactionFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Transaction?
    private let prefillWallet: Wallet?
    private let isTemplate: Bool
    @AppStorage("SaveMoney.didShowCategoryKeypadHint") private var didShowKeypadHint = false
    @State private var showKeypadHint = false
    @State private var failureTrigger = 0
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
    @State private var showingPersonPicker = false
    @State private var noteExpanded = false
    @State private var saveError: String?
    @State private var saveTrigger = 0
    @State private var selectionTrigger = 0
    @State private var saving = false
    @State private var keypadVisible = true
    private enum Field: Hashable { case note }
    @FocusState private var focus: Field?

    init(store: TransactionScreenStore, original: Transaction? = nil, onNeedsWallet: (() -> Void)? = nil, prefillKind: TransactionKind? = nil, prefillWallet: Wallet? = nil, prefillAmount: Int64 = 0, template: Transaction? = nil) {
        self.isTemplate = template != nil
        self.store = store
        self.original = original
        self.prefillWallet = prefillWallet
        self.onNeedsWallet = onNeedsWallet
        _expression = State(initialValue: AmountExpression(amount: original?.amount ?? template?.amount ?? prefillAmount))
        if let original {
            _draft = State(initialValue: TransactionDraft(amount: original.amount,
                kind: TransactionKind(rawValue: original.kindRaw) ?? .expense,
                date: original.date, note: original.note, wallet: original.wallet,
                toWallet: original.toWallet, category: original.category))
        } else if let template {
            _draft = State(initialValue: TransactionDraft(amount: template.amount,
                kind: TransactionKind(rawValue: template.kindRaw) ?? .expense, date: Date(), note: template.note,
                wallet: template.wallet, toWallet: template.toWallet, category: template.category))
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
                if original == nil && !store.wallets.contains(where: { !$0.isArchived && $0.isOwn }) {
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
                if noteExpanded || !draft.note.isEmpty {
                    FormField(label: "Ghi chú", text: $draft.note, prompt: "Không bắt buộc", multiline: true,
                              submitLabel: .return, focus: $focus, field: .note, identifier: "transaction.note")
                } else {
                    Button { noteExpanded = true; setKeypad(visible: false); focus = .note } label: {
                        Label("Thêm ghi chú", systemImage: "text.alignleft").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .accessibilityIdentifier("transaction.addNote")
                }
                if let message = store.errorMessage {
                    Text(message).foregroundStyle(.red)
                    Button("Tải lại dữ liệu") { reload() }
                        .frame(minHeight: 44)
                }
            }
            .padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            KindSelector(kind: $draft.kind)
                .padding(.horizontal)
                .padding(.vertical, Spacing.s)
                .background(Color(uiColor: .systemGroupedBackground))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil { inputControls }
        }
        .tint(Color(draft.kind == .income ? "Income" : draft.kind == .expense ? "Expense" : "Transfer"))
        .sensoryFeedback(.success, trigger: saveTrigger) { _, _ in !reduceMotion }
        .sensoryFeedback(.selection, trigger: selectionTrigger) { _, _ in !reduceMotion }
        .sensoryFeedback(.warning, trigger: failureTrigger) { _, _ in !reduceMotion }
        .keyboardDoneButton($focus)
        .scrollDismissesKeyboard(.interactively)
        .task {
            guard !initialized else { return }
            initialized = true
            if typeSize.isAccessibilitySize { keypadVisible = false }
            if !didShowKeypadHint {
                showKeypadHint = true
                didShowKeypadHint = true
            }
            if original == nil && !isTemplate {
                draft = TransactionFormSelection.restoring(draft, wallets: store.wallets.filter { $0.isOwn },
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
                draft = TransactionFormSelection.restoring(draft.changingKind(to: kind), wallets: store.wallets.filter { $0.isOwn }, categories: store.categories, recent: store.recent)
            }
            if let amount = prefill.amount { expression = AmountExpression(amount: amount); draft.amount = amount }
            routedPrefillNeedsSelection = true
            draft.category = nil; draft.toWallet = nil
            saveError = nil; store.addPrefill = nil
        }
        .onChange(of: draft.kind) { _, kind in
            if skipKindRestoration { skipKindRestoration = false; return }
            draft = TransactionFormSelection.restoring(draft.changingKind(to: kind),
                wallets: store.wallets.filter { $0.isOwn }, categories: store.categories, recent: store.recent,
                preserveWallet: original != nil)
            saveError = nil
        }
        .onChange(of: store.snapshotVersion) { _, _ in
            draft = TransactionFormSelection.reconcile(draft, wallets: store.wallets,
                categories: store.categories, editing: original)
        }
        .sheet(isPresented: $showingPersonPicker) {
            NavigationStack {
                List {
                    ForEach(store.wallets.filter { $0.isPerson && !$0.isArchived }, id: \.id) { person in
                        Button(person.name) { selectPayer(person) }
                            .frame(minHeight: 44)
                    }
                    NavigationLink {
                        DebtPersonForm(store: store, onSaved: { person in selectPayer(person) })
                    } label: { Label("Thêm người…", systemImage: "person.badge.plus") }
                }
                .navigationTitle("Người trả hộ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { showingPersonPicker = false } } }
            }
            .appSheet(.medium)
        }
        .navigationTitle(original == nil ? "Thêm giao dịch" : "Sửa giao dịch")
        .navigationBarTitleDisplayMode(.inline)
        // The Add tab is already named by the tab bar; hiding the bar gives the selector the top edge.
        .toolbar(isPresentedAsSheet ? .automatic : .hidden, for: .navigationBar)
        .appSheet(.large)
        .toolbar {
            if isPresentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
    }

    private var isPresentedAsSheet: Bool { original != nil || prefillWallet != nil || isTemplate }

    private var amountDisplay: some View {
        TransactionAmountDisplay(expression: expression, amount: draft.amount, kind: draft.kind,
                                 keypadVisible: keypadVisible) { setKeypad(visible: true) }
    }

    private var categoryPicker: some View {
        TransactionCategoryPicker(categories: visibleCategories, categoryIDs: visibleCategories.map(\.id), selectedID: draft.category?.id,
            revision: store.snapshotVersion,
            subtitles: draft.kind == .expense ? store.budgetSubtitles(on: draft.date) : [:],
            compactSubtitles: draft.kind == .expense ? store.budgetSubtitles(on: draft.date, compact: true) : [:],
            overBudget: draft.kind == .expense ? store.overBudgetCategories(on: draft.date) : []) { category in
                draft.category = category
                showKeypadHint = false
                selectionTrigger += 1
                saveError = nil
                setKeypad(visible: false)
            }.equatable()
    }

    private func walletPicker(destination: Bool) -> some View {
        let originalID = destination ? original?.toWallet?.id : original?.wallet?.id
        let wallets = TransactionFormSelection.wallets(store.wallets.filter { $0.isOwn || $0.id == originalID }, retaining: originalID,
            excluding: destination ? draft.wallet?.id : nil)
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel(destination ? "Đến ví" : draft.kind == .transfer ? "Từ ví" : "Ví")
            if wallets.isEmpty { Text("Không có ví phù hợp để chọn.").foregroundStyle(.secondary) }
            Group {
                if typeSize.isAccessibilitySize { VStack { walletChoices(wallets, destination: destination) } }
                else { ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 12) { walletChoices(wallets, destination: destination) } } }
            }
            if !destination && draft.kind == .expense {
                if let person = draft.wallet, person.isPerson { Label("\(person.name) trả hộ", systemImage: "person.crop.circle").font(.headline) }
                if !store.wallets.contains(where: { $0.isPerson && !$0.isArchived }) {
                    Text("Thêm người để ghi khoản họ trả hộ bạn.").font(.footnote).foregroundStyle(.secondary)
                }

            }
        }
    }

    private func selectPayer(_ person: Wallet) {
        draft.wallet = person
        saveError = nil
        setKeypad(visible: false)
        showingPersonPicker = false
    }

    @ViewBuilder private func walletChoices(_ wallets: [Wallet], destination: Bool) -> some View {
        ForEach(wallets, id: \.id) { wallet in
            let selected = (destination ? draft.toWallet?.id : draft.wallet?.id) == wallet.id
            Button {
                if destination { draft.toWallet = wallet }
                else { draft = TransactionFormSelection.selectingWallet(wallet, in: draft, available: store.wallets.filter { $0.isOwn }) }
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
        if !destination && draft.kind == .expense {
            Button {
                focus = nil
                setKeypad(visible: false)
                showingPersonPicker = true
            } label: {
                Label("Người khác trả", systemImage: "person.badge.plus")
                    .font(.headline).foregroundStyle(.primary)
                    .padding(Spacing.m)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 168, height: typeSize.isAccessibilitySize ? nil : 84, alignment: .leading)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("transaction.payer")
        }
    }

    private var dateSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Ngày · \(TransactionPresentation.shortDate(draft.date))")
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
                DatePicker("Ngày giao dịch", selection: Binding(get: { draft.date }, set: { draft.date = TransactionPresentation.selectedDay($0) }), displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(minHeight: 44)
            }
        }
    }

    private var inputControls: some View {
        TransactionInputControls(keypadVisible: keypadVisible, showKeypadHint: showKeypadHint,
            saveTitle: saveTitle, amountIsZero: draft.amount == 0,
            canSave: validationMessage == nil && !saving, saving: saving,
            message: inlineMessage, hideKeypad: { setKeypad(visible: false) },
            openKeypad: { focus = nil; setKeypad(visible: true) }, press: { key in
                expression.apply(key)
                draft.amount = expression.result ?? 0
                saveError = nil
            }, save: save)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try TransactionValidator.validate(draft, editing: original)
            try store.save(draft, editing: original?.id)
            saveTrigger += 1
            if original != nil || isTemplate || prefillWallet != nil { dismiss() }
            else {
                expression = AmountExpression()
                draft.amount = 0
                saveError = nil
                setKeypad(visible: true)
            }
        } catch { saveError = TransactionPresentation.errorMessage(error); failureTrigger += 1 }
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

@MainActor
private struct TransactionAmountDisplay: View {
    let expression: AmountExpression
    let amount: Int64
    let kind: TransactionKind
    let keypadVisible: Bool
    let openKeypad: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Text("Số tiền").font(.headline)
            if expression.hasOperator {
                Text(expression.displayText).font(.title3).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Button { openKeypad() } label: {
                HStack {
                    AmountText(amount: amount, style: .system(.largeTitle, design: .rounded).bold(), prefix: expression.hasOperator && amount >= 0 ? "= " : "")
                    Spacer(minLength: 8)
                    if !keypadVisible {
                        Image(systemName: "keyboard").foregroundStyle(.tint).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(TransactionPresentation.kindTitle(kind)), \(expression.hasOperator ? expression.displayText.replacingOccurrences(of: "+", with: "cộng").replacingOccurrences(of: "−", with: "trừ") + ", bằng " : "số tiền ")\(MoneyFormatter.string(from: amount).replacingOccurrences(of: "₫", with: "đồng"))")
            .accessibilityHint(keypadVisible ? "" : "Mở bàn phím số")
            .accessibilityIdentifier("transaction.amount")
        } }
    }
}

@MainActor
private struct TransactionCategoryPicker: View, Equatable {
    let categories: [Category]
    let categoryIDs: [UUID]
    let selectedID: UUID?
    let revision: UUID
    let subtitles: [UUID: String]
    let compactSubtitles: [UUID: String]
    let overBudget: Set<UUID>
    let onSelect: (Category) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.selectedID == rhs.selectedID &&
        lhs.categoryIDs == rhs.categoryIDs &&
        lhs.subtitles == rhs.subtitles && lhs.compactSubtitles == rhs.compactSubtitles && lhs.overBudget == rhs.overBudget
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Danh mục")
            if categories.isEmpty {
                Text("Không có danh mục phù hợp để chọn.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading) {
                ForEach(categories, id: \.id) { category in
                    let selected = selectedID == category.id
                    Button {
                        onSelect(category)
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
}

private struct TransactionInputControls: View {
    let keypadVisible: Bool
    let showKeypadHint: Bool
    let saveTitle: String
    let amountIsZero: Bool
    let canSave: Bool
    let saving: Bool
    let message: String?
    let hideKeypad: () -> Void
    let openKeypad: () -> Void
    let press: (MoneyFormatter.Key) -> Void
    let save: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            if keypadVisible {
                HStack {
                    Spacer()
                    Button { hideKeypad() } label: {
                        Label(typeSize.isAccessibilitySize ? "Ẩn phím" : "Ẩn bàn phím", systemImage: "keyboard.chevron.compact.down")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Ẩn bàn phím")
                    .accessibilityIdentifier("keypad.hide")
                }
                if showKeypadHint {
                    Text("Chọn danh mục để ẩn bàn phím").font(.caption).foregroundStyle(.secondary)
                }
                MoneyKeypad(showsOperators: true, press: press)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button(action: save) {
                Label(saveTitle, systemImage: amountIsZero ? "keyboard" : "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .appProminentButton()
            .disabled(!canSave)
            .accessibilityLabel(saveTitle)
            .accessibilityHint(amountIsZero ? "Mở bàn phím số" : "")
            .accessibilityAction(named: Text("Mở bàn phím số")) { openKeypad() }
            .accessibilityIdentifier("transaction.save")
            .overlay {
                if amountIsZero && !saving {
                    // The save action stays disabled; this separate hit area opens input.
                    Button { openKeypad() } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityHidden(true)
                }
            }
            if keypadVisible, let message = message {
                InlineError(message: message)
                    .accessibilityIdentifier("transaction.validation")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
