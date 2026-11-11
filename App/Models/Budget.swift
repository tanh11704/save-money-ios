import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID = UUID()
    var scopeRaw: String = "category"
    var category: Category? = nil
    var limit: Int64 = 0
    var startYear: Int = 0
    var startMonth: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init() {}

    var rule: BudgetRule? {
        guard (1...MoneyFormatter.maximumInput).contains(limit),
              let month = try? ReportingMonth(year: startYear, month: startMonth) else { return nil }
        let scope: BudgetRule.Scope
        switch scopeRaw {
        case "total":
            guard category == nil else { return nil }
            scope = .total
        case "category":
            guard let category, category.kindRaw == TransactionKind.expense.rawValue else { return nil }
            scope = .category(category.id)
        default: return nil
        }
        return BudgetRule(id: id, scope: scope, limit: limit, startMonth: month, isArchived: isArchived)
    }
}
