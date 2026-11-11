import Foundation
import SwiftData

struct CategoryDraft {
    var name = ""
    var kind: TransactionKind = .expense
    var icon = "tag"
}

@MainActor
struct CategoryService {
    let container: ModelContainer

    static func validate(_ draft: CategoryDraft, categories: [Category], editing original: Category? = nil,
                         hasTransactions: Bool = false) throws {
        let name = try ManagementValidation.name(draft.name)
        guard draft.kind != .transfer else { throw ManagementError.invalidKind }
        if let original, hasTransactions, original.kindRaw != draft.kind.rawValue { throw ManagementError.categoryInUse }
        guard !categories.contains(where: {
            $0.id != original?.id && $0.kindRaw == draft.kind.rawValue && ManagementValidation.matches($0.name, name)
        }) else { throw ManagementError.duplicateName }
        guard CategorySymbols.all.contains(where: { $0.name == draft.icon }) || draft.icon == original?.icon else {
            throw ManagementError.invalidIcon
        }
    }

    @discardableResult
    func create(_ draft: CategoryDraft) throws -> UUID {
        try ManagementPersistence(container: container).write { context in
            try Self.validate(draft, categories: context.fetch(FetchDescriptor<Category>()))
            let category = Category(name: try ManagementValidation.name(draft.name), kind: draft.kind, icon: draft.icon)
            context.insert(category)
            return category.id
        }
    }

    func update(id: UUID, with draft: CategoryDraft) throws {
        try ManagementPersistence(container: container).write { context in
            let categories = try context.fetch(FetchDescriptor<Category>())
            guard let category = categories.first(where: { $0.id == id }) else { throw ManagementError.missingRecord }
            let usedByTransactions = try context.fetch(FetchDescriptor<Transaction>()).contains { $0.category?.id == id }
            let usedByBudgets = try context.fetch(FetchDescriptor<Budget>()).contains { $0.category?.id == id }
            let usedByRecurring = try context.fetch(FetchDescriptor<RecurringRule>()).contains { $0.category?.id == id }
            let used = usedByTransactions || usedByBudgets || usedByRecurring
            try Self.validate(draft, categories: categories, editing: category, hasTransactions: used)
            category.name = try ManagementValidation.name(draft.name)
            category.kindRaw = draft.kind.rawValue
            category.icon = draft.icon
        }
    }

    func archive(id: UUID) throws { try setArchived(true, id: id) }
    func restore(id: UUID) throws { try setArchived(false, id: id) }

    private func setArchived(_ archived: Bool, id: UUID) throws {
        try ManagementPersistence(container: container).write { context in
            guard let category = try context.fetch(FetchDescriptor<Category>()).first(where: { $0.id == id }) else {
                throw ManagementError.missingRecord
            }
            category.isArchived = archived
        }
    }
}

struct CategorySymbols {
    struct Symbol: Identifiable {
        var id: String { name }
        let name: String
        let label: String
    }
    static let all: [Symbol] = [
        .init(name: "fork.knife", label: "Ăn uống"), .init(name: "bus", label: "Xe buýt"),
        .init(name: "house", label: "Nhà ở"), .init(name: "doc.text", label: "Hóa đơn"),
        .init(name: "bag", label: "Mua sắm"), .init(name: "cross.case", label: "Sức khỏe"),
        .init(name: "gamecontroller", label: "Giải trí"), .init(name: "tag", label: "Nhãn"),
        .init(name: "banknote", label: "Tiền"), .init(name: "plus.circle", label: "Thu nhập khác"),
        .init(name: "cup.and.saucer", label: "Cà phê"), .init(name: "cart", label: "Giỏ hàng"),
        .init(name: "car", label: "Ô tô"), .init(name: "bicycle", label: "Xe đạp"),
        .init(name: "airplane", label: "Máy bay"), .init(name: "tram", label: "Tàu điện"),
        .init(name: "fuelpump", label: "Nhiên liệu"), .init(name: "bolt", label: "Điện"),
        .init(name: "drop", label: "Nước"), .init(name: "wifi", label: "Internet"),
        .init(name: "phone", label: "Điện thoại"), .init(name: "book", label: "Sách"),
        .init(name: "graduationcap", label: "Học tập"), .init(name: "gift", label: "Quà tặng"),
        .init(name: "heart", label: "Trái tim"), .init(name: "film", label: "Phim"),
        .init(name: "music.note", label: "Âm nhạc"), .init(name: "pawprint", label: "Thú cưng"),
        .init(name: "briefcase", label: "Công việc"), .init(name: "creditcard", label: "Thẻ")
    ]
}
