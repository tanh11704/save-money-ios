import Foundation

/// A monthly spending limit. It repeats every month from `startMonth` until a
/// newer rule for the same scope replaces it, so editing a limit never rewrites
/// the limit that applied to earlier months.
struct BudgetRule: Equatable, Identifiable {
    enum Scope: Hashable {
        /// All expense categories together.
        case total
        case category(UUID)
    }

    var id: UUID = UUID()
    var scope: Scope
    /// Đồng, must be positive.
    var limit: Int64
    var startMonth: ReportingMonth
    /// Turned off from `startMonth` on; earlier months keep their old limit.
    var isArchived: Bool = false
}

struct BudgetService {
    enum Level: Int, Comparable {
        case normal, warning, over
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Threshold: Int, CaseIterable {
        case warning = 80, over = 100
    }

    struct Progress: Equatable {
        let scope: BudgetRule.Scope
        let limit: Int64
        let spent: Int64
        /// Negative once the limit is exceeded.
        let remaining: Int64
        let level: Level
        /// Display only; capped at 999,9% so a tiny limit cannot overflow the text.
        let percentageTenths: Int
        /// Display-only progress fraction; never used for money arithmetic.
        var fraction: Double { min(1, max(0, Double(spent) / Double(limit))) }
        var percentageText: String { StatsPercentage.text(tenths: percentageTenths) }
    }

    enum BudgetError: Error, Equatable {
        case invalidLimit
    }

    /// The rule in effect for `scope` during `month`, or nil when no limit applies.
    static func activeRule(for scope: BudgetRule.Scope, in month: ReportingMonth,
                           rules: [BudgetRule]) -> BudgetRule? {
        let candidate = rules
            .filter { $0.scope == scope && $0.startMonth <= month }
            .max { lhs, rhs in
                lhs.startMonth == rhs.startMonth ? lhs.id.uuidString < rhs.id.uuidString : lhs.startMonth < rhs.startMonth
            }
        guard let candidate, !candidate.isArchived else { return nil }
        return candidate
    }

    /// Progress for every scope that has an active limit in `month`.
    /// Only expenses count; transfers and income never touch a budget.
    /// Expenses in archived categories still count toward their limit.
    static func progress(month: ReportingMonth, rules: [BudgetRule],
                         transactions: [Transaction]) throws -> [Progress] {
        let totals = try BalanceCalculator.flowTotals(transactions: transactions, during: month.interval,
                                                      allowMissingCategory: true)
        let scopes = Set(rules.map(\.scope))
        return try scopes.compactMap { scope -> Progress? in
            guard let rule = activeRule(for: scope, in: month, rules: rules) else { return nil }
            let spent: Int64
            switch scope {
            case .total: spent = totals.expense
            case .category(let id): spent = totals.expenseByCategory[id, default: 0]
            }
            return try progress(scope: scope, limit: rule.limit, spent: spent)
        }
        .sorted(by: order)
    }

    static func progress(scope: BudgetRule.Scope, limit: Int64, spent: Int64) throws -> Progress {
        guard limit > 0 else { throw BudgetError.invalidLimit }
        let (remaining, overflow) = limit.subtractingReportingOverflow(spent)
        guard !overflow else { throw BalanceCalculator.CalculationError.overflow }
        return Progress(scope: scope, limit: limit, spent: spent, remaining: remaining,
                        level: try level(spent: spent, limit: limit),
                        percentageTenths: percentageTenths(spent: spent, limit: limit))
    }

    /// Integer-only comparison: spent * 100 >= limit * threshold.
    static func level(spent: Int64, limit: Int64) throws -> Level {
        guard limit > 0 else { throw BudgetError.invalidLimit }
        if try reached(.over, spent: spent, limit: limit) { return .over }
        if try reached(.warning, spent: spent, limit: limit) { return .warning }
        return .normal
    }

    /// Thresholds crossed by moving from `before` to `after` spending, lowest first.
    /// Used to send each 80% / 100% alert once, right when it is crossed.
    static func crossedThresholds(limit: Int64, before: Int64, after: Int64) throws -> [Threshold] {
        try Threshold.allCases.filter {
            try !reached($0, spent: before, limit: limit) && reached($0, spent: after, limit: limit)
        }
    }

    private static func reached(_ threshold: Threshold, spent: Int64, limit: Int64) throws -> Bool {
        // Compare in 128-bit space so no realistic amount can overflow.
        let lhs = spent.multipliedFullWidth(by: 100)
        let rhs = limit.multipliedFullWidth(by: Int64(threshold.rawValue))
        return (lhs.high, lhs.low) >= (rhs.high, rhs.low)
    }

    private static func percentageTenths(spent: Int64, limit: Int64) -> Int {
        guard spent > 0 else { return 0 }
        var ratio = Decimal(spent) * 1_000 / Decimal(limit)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return NSDecimalNumber(decimal: min(rounded, 9_999)).intValue
    }

    /// Total first, then the closest-to-limit categories.
    private static func order(_ lhs: Progress, _ rhs: Progress) -> Bool {
        switch (lhs.scope, rhs.scope) {
        case (.total, .category): return true
        case (.category, .total): return false
        case let (.category(a), .category(b)):
            if lhs.percentageTenths != rhs.percentageTenths { return lhs.percentageTenths > rhs.percentageTenths }
            return a.uuidString < b.uuidString
        case (.total, .total): return false
        }
    }
}
