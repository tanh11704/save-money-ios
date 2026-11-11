import SwiftUI

@MainActor
struct DebtPersonView: View {
    @ObservedObject var store: TransactionScreenStore
    private let initialPerson: Wallet
    private var person: Wallet { store.wallets.first { $0.id == initialPerson.id } ?? initialPerson }
    init(store: TransactionScreenStore, person: Wallet) { self.store = store; self.initialPerson = person }
    @State private var error: String?
    @State private var action: DebtPresentation.Action?
    @State private var paidOnBehalf = false
    @State private var editingName = false
    @State private var editingTransaction: Transaction?
    private var balance: Int64? { store.balanceValues[person.id] }
    var body: some View {
        List {
            Section {
                if let error { InlineError(message: error) }
                if person.isArchived {
                    Button("Khôi phục người này") {
                        do { try store.restoreWallet(person.id); error = nil } catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
                if let balance {
                    Card { VStack(alignment: .leading, spacing: 12) {
                        if balance == 0 { Illustration(name: "illus-debt-settled") }
                        Text(DebtPresentation.directionText(balance, person: person)).font(.headline).fixedSize(horizontal: false, vertical: true)
                        AmountText(amount: balance, style: .system(.largeTitle, design: .rounded).bold())
                    } }
                    if !person.isArchived {
                        if balance > 0 {
                            actionButton(.collect); actionButton(.lend)
                        } else if balance < 0 {
                            actionButton(.repay); actionButton(.borrow)
                        } else { actionButton(.lend); actionButton(.borrow) }
                        Button("Ghi khoản trả hộ", systemImage: "person.crop.circle") { paidOnBehalf = true }.frame(minHeight: 44)
                    }
                } else { Callout(level: .danger, title: "Chưa tính được số nợ") }
                if let summary = try? DebtPresentation.summary(person: person, transactions: store.transactions) {
                    ShareLink(item: summary) { Label("Chia sẻ tóm tắt", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                }
            }
            ForEach(TransactionGrouping.group(WalletLedger.transactions(for: person, in: store.transactions))) { day in
                Section(TransactionGrouping.title(for: day.date)) {
                    ForEach(day.transactions, id: \.id) { transaction in
                        Button { editingTransaction = transaction } label: {
                            LedgerRow(icon: "arrow.left.arrow.right", title: store.debtLabels[transaction.id]?.title ?? TransactionPresentation.title(transaction),
                                      subtitle: transaction.note,
                                      amount: TransactionPresentation.amount(transaction),
                                      trailingSubtitle: store.debtLabels[transaction.id].map { "Sau: " + MoneyFormatter.compact($0.balanceAfter) })
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel((store.debtLabels[transaction.id]?.title ?? TransactionPresentation.title(transaction)) + ", " + TransactionPresentation.amount(transaction) + (store.debtLabels[transaction.id].map { ", Sau giao dịch: " + DebtPresentation.balanceText($0.balanceAfter, person: person) } ?? ""))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.navigationTitle(person.name)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Sửa") { editingName = true }.frame(minHeight: 44) } }
        .sheet(item: $action) { action in NavigationStack { TransferSheet(store: store, mode: .debt(person: person, action: action)) } }
        .sheet(isPresented: $paidOnBehalf) { NavigationStack { TransactionFormView(store: store, prefillKind: .expense, prefillWallet: person) } }
        .sheet(isPresented: $editingName) { NavigationStack { DebtPersonForm(store: store, original: person) } }
        .sheet(item: $editingTransaction) { transaction in NavigationStack { TransactionFormView(store: store, original: transaction) } }
    }
    private func actionButton(_ action: DebtPresentation.Action) -> some View {
        Button(DebtPresentation.title(action, person: person)) { self.action = action }.appProminentButton().frame(minHeight: 44)
    }
}
