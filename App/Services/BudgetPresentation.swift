import Foundation

struct BudgetPresentation {
    static func name(for scope: BudgetRule.Scope, categories: [Category]) -> String {
        switch scope {
        case .total: return "Hạn mức tổng"
        case .category(let id): return categories.first { $0.id == id }?.name ?? "Danh mục không tồn tại"
        }
    }
    static func usage(_ progress: BudgetService.Progress) -> String {
        String(MoneyFormatter.string(from: progress.spent).dropLast(2)) + " / " + MoneyFormatter.string(from: progress.limit)
    }
    static func remaining(_ progress: BudgetService.Progress) -> String {
        (progress.remaining < 0 ? "Vượt " : "Còn ") + MoneyFormatter.string(from: progress.remaining < 0 ? -progress.remaining : progress.remaining)
    }
    static func categoryLimitsExceedTotal(month: ReportingMonth, rules: [BudgetRule], replacing scope: BudgetRule.Scope, limit: Int64) -> Bool {
        guard (1...MoneyFormatter.maximumInput).contains(limit) else { return false }
        var rules = rules.filter { $0.scope != scope || $0.startMonth != month }
        rules.append(BudgetRule(scope: scope, limit: limit, startMonth: month))
        guard let total = BudgetService.activeRule(for: .total, in: month, rules: rules)?.limit else { return false }
        var sum: Int64 = 0
        for scope in Set(rules.map(\.scope)) {
            guard case .category = scope,
                  let rule = BudgetService.activeRule(for: scope, in: month, rules: rules) else { continue }
            let next = sum.addingReportingOverflow(rule.limit)
            if next.overflow { return true }
            sum = next.partialValue
        }
        return sum > total
    }
    static func voiceOver(_ progress: BudgetService.Progress, name: String) -> String {
        "\(name), đã chi \(MoneyFormatter.string(from: progress.spent)) trên \(MoneyFormatter.string(from: progress.limit)), \(remaining(progress))"
            .replacingOccurrences(of: "₫", with: "đồng")
    }
}
