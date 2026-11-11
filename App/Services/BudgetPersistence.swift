import Foundation
import SwiftData

@MainActor
struct BudgetPersistence {
    enum ValidationError: LocalizedError {
        case invalidLimit, invalidCategory
        var errorDescription: String? {
            switch self {
            case .invalidLimit: return "Hạn mức phải nằm trong 1…999.999.999.999 ₫."
            case .invalidCategory: return "Chỉ đặt hạn mức cho danh mục chi đang dùng."
            }
        }
    }

    static func setLimit(_ limit: Int64, scope: BudgetRule.Scope, from month: ReportingMonth, context: ModelContext) throws {
        guard (1...MoneyFormatter.maximumInput).contains(limit) else { throw ValidationError.invalidLimit }
        try write(limit: limit, archived: false, scope: scope, month: month, context: context)
    }

    static func turnOff(scope: BudgetRule.Scope, from month: ReportingMonth, context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<Budget>()).compactMap(\.rule)
        guard let existing = BudgetService.activeRule(for: scope, in: month, rules: rules) else { return }
        try write(limit: existing.limit, archived: true, scope: scope, month: month, context: context)
    }

    private static func write(limit: Int64, archived: Bool, scope: BudgetRule.Scope, month: ReportingMonth, context: ModelContext) throws {
        let category: Category?
        switch scope {
        case .total: category = nil
        case .category(let id):
            guard let found = try context.fetch(FetchDescriptor<Category>()).first(where: { $0.id == id }),
                  found.kindRaw == TransactionKind.expense.rawValue, archived || !found.isArchived else {
                throw ValidationError.invalidCategory
            }
            category = found
        }
        let matches = try context.fetch(FetchDescriptor<Budget>()).filter {
            $0.rule?.scope == scope && $0.startYear == month.year && $0.startMonth == month.month
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let budget = matches.last ?? Budget()
        if matches.isEmpty { context.insert(budget) }
        // Normalize any duplicate rows imported from an older backup.
        for duplicate in matches.dropLast() { context.delete(duplicate) }
        budget.scopeRaw = category == nil ? "total" : "category"
        budget.category = category; budget.limit = limit
        budget.startYear = month.year; budget.startMonth = month.month; budget.isArchived = archived
        // Caller owns the transaction and posts ledgerDidChange after saving.
    }
}
