import SwiftUI

@MainActor
struct CategoryListView: View {
    @ObservedObject var store: TransactionScreenStore
    @State private var showingAdd = false
    @State private var editing: Category?
    @State private var archiveCandidate: Category?
    @State private var confirmingArchive = false
    @State private var archivedExpanded = false
    @State private var message: String?

    var body: some View {
        List {
            if let message = message ?? store.errorMessage { Text(message).foregroundStyle(.red) }
            categorySection(.expense)
            categorySection(.income)
            Section {
                DisclosureGroup("Đã lưu trữ (\(store.categories.filter { $0.isArchived }.count))", isExpanded: $archivedExpanded) {
                    ForEach(store.categories.filter { $0.isArchived }, id: \.id) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { editing = category } label: { categoryRow(category) }.buttonStyle(.plain)
                            Button { restore(category) } label: {
                                Text("Khôi phục \(category.name)").frame(minHeight: 44)
                            }.buttonStyle(.borderless)
                        }
                    }
                }.frame(minHeight: 44)
            }
        }
        .navigationTitle("Quản lý danh mục")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Thêm danh mục")
            }
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { CategoryFormView(store: store) } }
        .sheet(item: $editing) { category in NavigationStack { CategoryFormView(store: store, original: category) } }
        .confirmationDialog("Lưu trữ danh mục?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Lưu trữ") {
                guard let category = archiveCandidate else { return }
                do { try store.archiveCategory(category.id); message = nil }
                catch { message = TransactionPresentation.errorMessage(error) }
                archiveCandidate = nil
            }
            Button("Hủy", role: .cancel) { archiveCandidate = nil }
        } message: {
            Text("Không hiện khi nhập mới. Lịch sử và số dư giữ nguyên.")
        }
    }

    private func categorySection(_ kind: TransactionKind) -> some View {
        Section(TransactionPresentation.kindTitle(kind)) {
            let categories = store.categories.filter { !$0.isArchived && $0.kindRaw == kind.rawValue }
            if categories.isEmpty { Text("Chưa có danh mục.").foregroundStyle(.secondary) }
            ForEach(categories, id: \.id) { category in
                Button { editing = category } label: { categoryRow(category) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Chạm hai lần để sửa danh mục")
                    .accessibilityAction(named: Text("Lưu trữ danh mục")) { requestArchive(category) }
                    .swipeActions(allowsFullSwipe: false) {
                        Button { requestArchive(category) } label: { Label("Lưu trữ", systemImage: "archivebox") }
                            .tint(.orange)
                    }
            }
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { CategoryIcon(icon: category.icon); Text(category.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
            Text(category.kindRaw == "income" ? "Thu" : "Chi").font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
    private func requestArchive(_ category: Category) { archiveCandidate = category; confirmingArchive = true }
    private func restore(_ category: Category) {
        do { try store.restoreCategory(category.id); message = nil }
        catch { message = TransactionPresentation.errorMessage(error) }
    }
}
