import SwiftUI

@MainActor
struct WalletDetailView: View {
    @ObservedObject var store: TransactionScreenStore
    private let initialWallet: Wallet
    private var wallet: Wallet { store.wallets.first { $0.id == initialWallet.id } ?? initialWallet }
    init(store: TransactionScreenStore, wallet: Wallet) { self.store = store; self.initialWallet = wallet }
    @State private var editingWallet = false
    @State private var showingTransfer = false
    @State private var adjusting = false
    @State private var adding: AddKind?
    @State private var editingTransaction: Transaction?
    @State private var kind: String = "all"
    private struct AddKind: Identifiable { let kind: TransactionKind; var id: String { kind.rawValue } }
    private var transactions: [Transaction] { WalletLedger.transactions(for: wallet, in: store.transactions).filter { kind == "all" || $0.kindRaw == kind } }
    var body: some View {
        List {
            Section {
                WalletCard(wallet: wallet, balance: store.balanceValues[wallet.id])
                if !wallet.isArchived {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        actionTile("Chi", icon: "arrow.down.circle.fill", tint: Color("Expense")) { adding = AddKind(kind: .expense) }
                        actionTile("Thu", icon: "arrow.up.circle.fill", tint: Color("Income")) { adding = AddKind(kind: .income) }
                        actionTile("Chuyển", icon: "arrow.left.arrow.right.circle.fill", tint: Color("Transfer")) { showingTransfer = true }
                        actionTile("Điều chỉnh", icon: "slider.horizontal.3", tint: .gray) { adjusting = true }
                            .accessibilityHint("Nhập số dư thực tế của ví")
                            .accessibilityIdentifier("wallet.adjust")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Picker("Lọc giao dịch", selection: $kind) {
                    Text("Tất cả").tag("all"); Text("Chi").tag("expense"); Text("Thu").tag("income"); Text("Chuyển").tag("transfer")
                }.pickerStyle(.menu).frame(minHeight: 44)
            }
            let balances = try? WalletLedger.runningBalances(wallet: wallet, transactions: store.transactions)
            ForEach(TransactionGrouping.group(transactions)) { day in
                Section {
                    ForEach(day.transactions, id: \.id) { transaction in
                        Button { editingTransaction = transaction } label: { TransactionRow(transaction: transaction, debt: store.debtLabels[transaction.id]) }.buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading) {
                        Text(TransactionGrouping.title(for: day.date))
                        if let balance = balances?[day.date] { Text("Cuối ngày: " + MoneyFormatter.string(from: balance)).monospacedDigit() }
                        else { Text("Chưa tính được số dư cuối ngày") }
                    }
                }
            }
        }.navigationTitle(wallet.name)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Sửa") { editingWallet = true }.frame(minHeight: 44) } }
        .sheet(isPresented: $editingWallet) { NavigationStack { WalletFormView(store: store, original: wallet) } }
        .sheet(isPresented: $showingTransfer) { NavigationStack { TransferSheet(store: store, source: wallet) } }
        .sheet(isPresented: $adjusting) { NavigationStack { BalanceAdjustmentSheet(store: store, wallet: wallet) } }
        .sheet(item: $adding) { selection in NavigationStack { TransactionFormView(store: store, prefillKind: selection.kind, prefillWallet: wallet) } }
        .sheet(item: $editingTransaction) { transaction in NavigationStack { TransactionFormView(store: store, original: transaction) } }
    }

    private func actionTile(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint).accessibilityHidden(true)
                Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Enter the real balance; the app records only the difference as a dated adjustment.
@MainActor
struct BalanceAdjustmentSheet: View {
    @ObservedObject var store: TransactionScreenStore
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var magnitude: Int64 = 0
    @State private var isNegative = false
    @State private var touched = false
    @State private var keypadVisible = true
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?
    @State private var initialized = false
    private enum Field: Hashable { case note }
    @FocusState private var focus: Field?

    private var current: Int64? { store.balanceValues[wallet.id] }
    private var actual: Int64 { isNegative ? -magnitude : magnitude }
    private var delta: Int64? {
        guard let current else { return nil }
        return try? BalanceAdjustmentService.difference(current: current, actual: actual)
    }
    private var deltaProblem: String? {
        guard let current else { return "Chưa tính được số dư hiện tại." }
        do { _ = try BalanceAdjustmentService.difference(current: current, actual: actual); return nil }
        catch { return TransactionPresentation.errorMessage(error) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon).font(.title2)
                        .foregroundStyle(.tint).frame(width: 44, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wallet.name).font(.title3.weight(.semibold))
                        Text("Trong app: \(current.map(MoneyFormatter.string(from:)) ?? "chưa tính được")")
                            .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Số dư thực tế")
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Button { focus = nil; keypadVisible.toggle() } label: {
                                HStack {
                                    Text(MoneyFormatter.string(from: actual)).font(.system(.largeTitle, design: .rounded).bold())
                                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                                        .foregroundStyle(touched ? Color.primary : Color.secondary)
                                    Spacer(minLength: 8)
                                    Image(systemName: keypadVisible ? "keyboard.chevron.compact.down" : "keyboard").foregroundStyle(.tint).accessibilityHidden(true)
                                }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Số dư thực tế \(MoneyFormatter.string(from: actual))".replacingOccurrences(of: "₫", with: "đồng"))
                            .accessibilityHint("Ẩn hoặc hiện bàn phím số tiền")
                            .accessibilityIdentifier("adjust.amount")
                            Divider()
                            Toggle(isOn: $isNegative) { Label("Đang âm (nợ thẻ)", systemImage: "minus.circle") }
                                .frame(minHeight: 44)
                        }
                    }
                    if !touched { Text("Gõ số dư bạn thấy trong ngân hàng hoặc ví thật.").font(.footnote).foregroundStyle(.secondary) }
                }
                differenceCard
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Ngày điều chỉnh")
                    DatePicker("Ngày điều chỉnh", selection: Binding(get: { date }, set: { date = TransactionPresentation.selectedDay($0) }),
                               in: ...Date(), displayedComponents: .date)
                        .labelsHidden().dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(minHeight: 44)
                }
                FormField(label: "Ghi chú", text: $note, prompt: "Ví dụ: Quên ghi tiền gửi xe", multiline: true,
                          submitLabel: .return, focus: $focus, field: .note, identifier: "adjust.note")
                Callout(level: .info, title: "Không tính vào thu/chi", message: "Phần chênh lệch được ghi riêng, không ảnh hưởng thống kê và ngân sách.")
                if let error { InlineError(message: error) }
            }.padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                PrimaryActionBar(title: delta == nil && touched ? "Số dư đã khớp" : "Điều chỉnh số dư", systemImage: "slider.horizontal.3",
                                 enabled: delta != nil, identifier: "adjust.save", action: save) {
                    if keypadVisible {
                        MoneyKeypad { key in
                            // The prefilled current balance is replaced by the first key press.
                            if !touched { magnitude = 0; touched = true }
                            magnitude = MoneyFormatter.applying(key, to: magnitude)
                            error = nil
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton($focus)
        .navigationTitle("Điều chỉnh số dư")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .appSheet(.large)
        .onChange(of: isNegative) { _, _ in touched = true; error = nil }
        .task {
            guard !initialized else { return }
            initialized = true
            if typeSize.isAccessibilitySize { keypadVisible = false }
            if let current {
                magnitude = WalletService.magnitude(of: current)
                isNegative = current < 0
            }
        }
    }

    @ViewBuilder private var differenceCard: some View {
        if touched {
            if let delta {
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        Label(delta > 0 ? "Tăng" : "Giảm", systemImage: delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(delta > 0 ? Color("Income") : Color("Expense"))
                        Spacer()
                        Text((delta > 0 ? "+" : "−") + MoneyFormatter.string(from: abs(delta)))
                            .font(.title3.bold()).monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Chênh lệch \(delta > 0 ? "tăng" : "giảm") \(MoneyFormatter.string(from: abs(delta)))".replacingOccurrences(of: "₫", with: "đồng"))
            } else if let deltaProblem {
                Callout(level: .info, title: deltaProblem)
            }
        }
    }

    private func save() {
        do {
            try store.adjustBalance(walletID: wallet.id, to: actual, date: date, note: note)
            dismiss()
        } catch { self.error = TransactionPresentation.errorMessage(error) }
    }
}
