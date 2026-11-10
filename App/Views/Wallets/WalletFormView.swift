import SwiftUI

@MainActor
struct WalletFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Wallet?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: WalletKind
    @State private var magnitude: Int64
    @State private var isDebt: Bool
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tên ví").font(.headline)
                TextField("Tên ví, tối đa 30 ký tự", text: $name)
                    .textFieldStyle(.roundedBorder).focused($nameFocused).frame(minHeight: 44)
                    .accessibilityIdentifier("wallet.name")
                if let nameMessage { Text(nameMessage).font(.footnote).foregroundStyle(.red) }
                Picker("Loại ví", selection: $kind) {
                    ForEach(WalletKind.allCases, id: \.self) { kind in Label(kind.title, systemImage: kind.icon).tag(kind) }
                }.pickerStyle(.menu).frame(minHeight: 44)
                Text("Số dư ban đầu").font(.headline)
                Text(WalletService.displayOpening(magnitude: magnitude, isDebt: isDebt))
                    .font(.largeTitle).monospacedDigit().lineLimit(1).minimumScaleFactor(0.25)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .accessibilityLabel("Số dư ban đầu \(WalletService.displayOpening(magnitude: magnitude, isDebt: isDebt))")
                Toggle("Đang nợ", isOn: $isDebt).frame(minHeight: 44)
                if let amountMessage { Text(amountMessage).font(.footnote).foregroundStyle(.red) }
                openingBalanceWarning
                if let message = saveError {
                    Text(message).font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if nameFocused {
                    Button("Xong tên ví") { nameFocused = false }.frame(minHeight: 44)
                } else {
                    MoneyKeypad { magnitude = MoneyFormatter.applying($0, to: magnitude); saveError = nil }
                    Button(action: save) { Text("Lưu ví").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                        .disabled(validationMessage != nil)
                }
            }.padding(8).background(.bar)
        }
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Số dư hiện tại của ví sẽ thay đổi theo").font(.headline)
                            Text("Trước: \(MoneyFormatter.string(from: preview.before))")
                            Text("Sau: \(MoneyFormatter.string(from: preview.after))")
                        }
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
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
