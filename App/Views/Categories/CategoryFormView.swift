import SwiftUI

@MainActor
struct CategoryFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Category?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: CategoryDraft
    @State private var saveError: String?

    init(store: TransactionScreenStore, original: Category? = nil) {
        self.store = store
        self.original = original
        _draft = State(initialValue: CategoryDraft(name: original?.name ?? "",
            kind: TransactionKind(rawValue: original?.kindRaw ?? "expense") ?? .expense, icon: original?.icon ?? "tag"))
    }

    private var lockedKind: Bool { original.map { store.categoryKindIsLocked($0.id) } ?? false }
    private var validationMessage: String? {
        do {
            try CategoryService.validate(draft, categories: store.categories, editing: original, hasTransactions: lockedKind)
            return nil
        } catch { return TransactionPresentation.errorMessage(error) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tên danh mục").font(.headline)
                TextField("Tên danh mục, tối đa 30 ký tự", text: $draft.name, axis: .vertical).lineLimit(1...3)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("category.name")
                if let message = saveError ?? validationMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Loại danh mục", selection: $draft.kind) {
                    Text("Chi").tag(TransactionKind.expense)
                    Text("Thu").tag(TransactionKind.income)
                }.pickerStyle(.menu).disabled(lockedKind).frame(minHeight: 44)
                if lockedKind {
                    Text("Danh mục đã có giao dịch, hạn mức hoặc quy tắc định kỳ nên không thể đổi loại. Muốn khác loại, hãy tạo danh mục mới.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("Biểu tượng").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 88))], spacing: 8) {
                    ForEach(CategorySymbols.all) { symbol in
                        Button { draft.icon = symbol.name; saveError = nil } label: {
                            VStack(spacing: 6) {
                                Image(systemName: symbol.name).font(.title2).accessibilityHidden(true)
                                Text(symbol.label).font(.caption).fixedSize(horizontal: false, vertical: true)
                                if draft.icon == symbol.name { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .tint(draft.icon == symbol.name ? Color.accentColor : Color.secondary)
                        .accessibilityLabel("Biểu tượng \(symbol.label)")
                        .accessibilityAddTraits(draft.icon == symbol.name ? [.isSelected] : [])
                    }
                }
                Button(action: save) { Text("Lưu danh mục").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).disabled(validationMessage != nil)
            }.padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(original == nil ? "Thêm danh mục" : "Sửa danh mục")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        .onChange(of: draft.name) { _, _ in saveError = nil }
        .onChange(of: draft.kind) { _, _ in saveError = nil }
    }

    private func save() {
        do { try store.saveCategory(draft, editing: original?.id); dismiss() }
        catch { saveError = TransactionPresentation.errorMessage(error) }
    }
}
