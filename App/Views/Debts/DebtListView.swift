import SwiftUI

@MainActor
struct DebtListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var adding = false
    @State private var settledExpanded = false
    @State private var archivedExpanded = false
    @State private var error: String?
    private var people: [Wallet] { store.wallets.filter { $0.isPerson && (!$0.isArchived || (store.balanceValues[$0.id] ?? 0) != 0) } }
    private func balance(_ person: Wallet) -> Int64 { store.balanceValues[person.id] ?? 0 }
    var body: some View {
        List {
            if let worth = store.netWorth {
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            StatTile(title: "Họ nợ bạn", value: MoneyFormatter.string(from: worth.receivable), icon: "person.badge.plus")
                            StatTile(title: "Bạn nợ", value: MoneyFormatter.string(from: worth.payable), icon: "person.badge.minus")
                        }
                        VStack {
                            StatTile(title: "Họ nợ bạn", value: MoneyFormatter.string(from: worth.receivable), icon: "person.badge.plus")
                            StatTile(title: "Bạn nợ", value: MoneyFormatter.string(from: worth.payable), icon: "person.badge.minus")
                        }
                    }
                    LabeledContent("Tài sản ròng", value: MoneyFormatter.string(from: worth.net)).font(.subheadline)
                }
            }
            if let error { Callout(level: .warning, title: "Chưa thể lưu trữ", message: error) }
            if people.isEmpty {
                EmptyState(image: "illus-empty-debt", title: "Chưa có người", message: "Ghi nhận khoản vay và trả hộ", symbol: "person.2", actionTitle: "Thêm người") { adding = true }
            }
            if people.contains(where: { balance($0) > 0 }) { Section("Họ nợ bạn") { ForEach(people.filter { balance($0) > 0 }.sorted { balance($0) > balance($1) }, id: \.id) { row($0) } } }
            if people.contains(where: { balance($0) < 0 }) { Section("Bạn nợ họ") { ForEach(people.filter { balance($0) < 0 }.sorted { balance($0) < balance($1) }, id: \.id) { row($0) } } }
            DisclosureGroup("Đã xong (\(people.filter { balance($0) == 0 }.count))", isExpanded: $settledExpanded) {
                ForEach(people.filter { balance($0) == 0 }, id: \.id) { row($0) }
            }.frame(minHeight: 44)
            DisclosureGroup("Đã lưu trữ", isExpanded: $archivedExpanded) {
                ForEach(store.wallets.filter { $0.isPerson && $0.isArchived && (store.balanceValues[$0.id] ?? 0) == 0 }, id: \.id) { person in
                    row(person)
                }
            }.frame(minHeight: 44)
        }.navigationTitle("Sổ nợ")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Thêm người", systemImage: "plus") { adding = true }.frame(minHeight: 44) } }
        .sheet(isPresented: $adding) { NavigationStack { DebtPersonForm(store: store) } }
    }
    private func row(_ person: Wallet) -> some View {
        NavigationLink { DebtPersonView(store: store, person: person) } label: {
            LedgerRow(icon: "person.crop.circle", title: person.name,
                      subtitle: (person.isArchived ? "Đã lưu trữ · " : "") + (balance(person) >= 0 ? "nợ bạn" : "bạn nợ") + (store.lastActivityByWallet[person.id].map { " · " + TransactionPresentation.shortDate($0) } ?? ""),
                      amount: MoneyFormatter.string(from: balance(person) < 0 ? -balance(person) : balance(person)),
                      tint: balance(person) < 0 ? Color("Expense") : Color("Income"))
        }
        .swipeActions(allowsFullSwipe: false) {
            Button(person.isArchived ? "Khôi phục" : "Lưu trữ", systemImage: person.isArchived ? "arrow.uturn.backward" : "archivebox") {
                do {
                    if person.isArchived { try store.restoreWallet(person.id) }
                    else { try store.archiveWallet(person.id) }
                    error = nil
                } catch { self.error = error.localizedDescription }
            }.tint(.orange)
        }
    }
}

@MainActor
struct DebtPersonForm: View {
    @ObservedObject var store: TransactionScreenStore
    var original: Wallet? = nil
    var onSaved: ((Wallet) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    private enum Field: Hashable { case name }
    @FocusState private var focus: Field?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                FormField(label: "Tên người", text: $name, prompt: "Ví dụ: anh Nam", error: error, limit: 30,
                          focus: $focus, field: .name, onSubmit: save, identifier: "debt.name")
                Text("Ghi khoản cho vay, đi vay và trả hộ với người này trong Sổ nợ.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryActionBar(title: original == nil ? "Thêm người" : "Lưu tên", enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                             identifier: "debt.save", action: save)
        }
        .scrollDismissesKeyboard(.interactively).keyboardDoneButton($focus)
        .navigationTitle(original == nil ? "Thêm người" : "Sửa tên")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .appSheet(.compact)
        .onAppear { if original == nil { focus = .name } }
        .onChange(of: name) { _, _ in error = nil }
        .task { name = original?.name ?? "" }
    }

    private func save() {
        do {
            let existingIDs = Set(store.wallets.map(\.id))
            try store.saveWallet(WalletDraft(name: name, kind: .person), editing: original?.id)
            if let person = store.wallets.first(where: {
                $0.isPerson && (original != nil ? $0.id == original?.id : !existingIDs.contains($0.id))
            }), let onSaved {
                onSaved(person)
            } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
