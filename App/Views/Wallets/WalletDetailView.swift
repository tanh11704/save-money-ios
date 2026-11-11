import SwiftUI

@MainActor
struct WalletDetailView: View {
    @ObservedObject var store: TransactionScreenStore
    let wallet: Wallet
    @State private var editingWallet = false
    @State private var showingTransfer = false
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
                    HStack {
                        Button { adding = AddKind(kind: .expense) } label: { Label("Chi", systemImage: "arrow.down.circle") }
                        Button { adding = AddKind(kind: .income) } label: { Label("Thu", systemImage: "arrow.up.circle") }
                        Button { showingTransfer = true } label: { Label("Chuyển", systemImage: "arrow.left.arrow.right.circle") }
                    }.buttonStyle(.bordered).frame(minHeight: 44)
                }
                Picker("Lọc giao dịch", selection: $kind) {
                    Text("Tất cả").tag("all"); Text("Chi").tag("expense"); Text("Thu").tag("income"); Text("Chuyển").tag("transfer")
                }.pickerStyle(.menu).frame(minHeight: 44)
            }
            let balances = try? WalletLedger.runningBalances(wallet: wallet, transactions: store.transactions)
            ForEach(TransactionGrouping.group(transactions)) { day in
                Section {
                    ForEach(day.transactions, id: \.id) { transaction in
                        Button { editingTransaction = transaction } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain)
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
        .sheet(item: $adding) { selection in NavigationStack { TransactionFormView(store: store, prefillKind: selection.kind, prefillWallet: wallet) } }
        .sheet(item: $editingTransaction) { transaction in NavigationStack { TransactionFormView(store: store, original: transaction) } }
    }
}
