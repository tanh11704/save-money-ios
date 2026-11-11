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
                    StatTile(title: "Người khác nợ bạn", value: MoneyFormatter.string(from: worth.receivable), icon: "person.badge.plus")
                    StatTile(title: "Bạn đang nợ", value: MoneyFormatter.string(from: worth.payable), icon: "person.badge.minus")
                    StatTile(title: "Tài sản ròng", value: MoneyFormatter.string(from: worth.net), icon: "equal.circle")
                }
            }
            if let error { Callout(level: .warning, title: "Chưa thể lưu trữ", message: error) }
            if people.isEmpty {
                EmptyState(image: "illus-empty-debt", title: "Chưa có người", message: "Ghi nhận khoản vay và trả hộ", symbol: "person.2", actionTitle: "Thêm người") { adding = true }
            }
            Section("Họ nợ bạn") { ForEach(people.filter { balance($0) > 0 }.sorted { balance($0) > balance($1) }, id: \.id) { row($0) } }
            Section("Bạn nợ họ") { ForEach(people.filter { balance($0) < 0 }.sorted { balance($0) < balance($1) }, id: \.id) { row($0) } }
            DisclosureGroup("Đã xong (\(people.filter { balance($0) == 0 }.count))", isExpanded: $settledExpanded) {
                ForEach(people.filter { balance($0) == 0 }, id: \.id) { row($0) }
            }.frame(minHeight: 44)
            DisclosureGroup("Đã lưu trữ", isExpanded: $archivedExpanded) {
                ForEach(store.wallets.filter { $0.isPerson && $0.isArchived && (store.balanceValues[$0.id] ?? 0) == 0 }, id: \.id) { person in
                    Button("Khôi phục \(person.name)") {
                        do { try store.restoreWallet(person.id); error = nil } catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
            }.frame(minHeight: 44)
        }.navigationTitle("Sổ nợ")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Thêm người", systemImage: "plus") { adding = true }.frame(minHeight: 44) } }
        .sheet(isPresented: $adding) { NavigationStack { DebtPersonForm(store: store) } }
    }
    private func row(_ person: Wallet) -> some View {
        NavigationLink { DebtPersonView(store: store, person: person) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(String(person.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(CategoryStyle.tint(for: person.name), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name).font(.headline)
                    if person.isArchived { Label("Đã lưu trữ", systemImage: "archivebox").font(.caption) }
                    Text(DebtPresentation.balanceText(balance(person), person: person)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if let date = WalletLedger.transactions(for: person, in: store.transactions).map(\.date).max() { Text(TransactionPresentation.shortDate(date)).font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(minHeight: 44)
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
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    private enum Field: Hashable { case name }
    @FocusState private var focus: Field?
    var body: some View {
        Form {
            TextField("Tên, tối đa 30 ký tự", text: $name).focused($focus, equals: .name).submitLabel(.done).onSubmit { focus = nil }.frame(minHeight: 44).accessibilityIdentifier("debt.name")
            if let error { InlineError(message: error) }
            Button("Lưu") {
                do { try store.saveWallet(WalletDraft(name: name, kind: .person), editing: original?.id); dismiss() }
                catch { self.error = error.localizedDescription }
            }.frame(minHeight: 44)
        }.scrollDismissesKeyboard(.interactively).keyboardDoneButton($focus)
        .navigationTitle(original == nil ? "Thêm người" : "Sửa tên")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .task { name = original?.name ?? "" }
    }
}
