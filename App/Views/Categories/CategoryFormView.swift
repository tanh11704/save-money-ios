import SwiftUI

@MainActor
struct CategoryFormView: View {
    @ObservedObject var store: TransactionScreenStore
    let original: Category?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum Field: Hashable { case name }
    @FocusState private var focus: Field?
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

    private static let kindOptions: [(value: TransactionKind, title: String, icon: String)] = [
        (.expense, "Chi", "arrow.down.circle"), (.income, "Thu", "arrow.up.circle"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Preview of how the category will look everywhere else in the app.
                HStack(spacing: Spacing.m) {
                    CategoryIcon(icon: draft.icon, size: 56)
                    Text(draft.name.isEmpty ? "Danh mục mới" : draft.name)
                        .font(.title3.weight(.semibold)).foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                FormField(label: "Tên danh mục", text: $draft.name, prompt: "Ví dụ: Cà phê, Gửi xe",
                          error: draft.name.isEmpty ? nil : (saveError ?? validationMessage), limit: 30,
                          focus: $focus, field: .name, onSubmit: { focus = nil }, identifier: "category.name")
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        FieldLabel("Loại")
                        if lockedKind {
                            Label("Đã khóa", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            InfoButton(text: "Danh mục đã có giao dịch, hạn mức hoặc quy tắc định kỳ. Tạo danh mục mới để dùng loại khác.")
                        }
                    }
                    ChoiceChips(options: Self.kindOptions, selection: $draft.kind, disabled: lockedKind)
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FieldLabel("Biểu tượng")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 120 : 72), spacing: 8)], spacing: 12) {
                        ForEach(CategorySymbols.all) { symbol in
                            let selected = draft.icon == symbol.name
                            Button { draft.icon = symbol.name; saveError = nil } label: {
                                VStack(spacing: 6) {
                                    CategoryIcon(icon: symbol.name, size: 44)
                                        .overlay(alignment: .topTrailing) {
                                            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color("OnAccent"), Color.accentColor).accessibilityHidden(true) }
                                        }
                                    Text(symbol.label).font(.caption2).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76).padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Biểu tượng \(symbol.label)")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }
                }
            }.padding()
        }
        .appScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                PrimaryActionBar(title: original == nil ? "Thêm danh mục" : "Lưu thay đổi", enabled: validationMessage == nil, action: save)
            }
        }
        .appSheet(.large)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton($focus)
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
