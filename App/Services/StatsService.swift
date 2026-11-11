import Foundation

struct StatsService {
    struct CategoryKey: Hashable {
        let kind: TransactionKind
        let categoryID: UUID?
        var isOther = false
    }
    struct CategoryTotal: Identifiable {
        var id: CategoryKey { key }
        let key: CategoryKey
        let name: String
        let icon: String
        let amount: Int64
        let percentageTenths: Int
        var percentageText: String { StatsPercentage.text(tenths: percentageTenths) }
    }
    struct Report {
        let month: ReportingMonth
        let income: Int64
        let expense: Int64
        let difference: Int64
        let expenses: [CategoryTotal]
        let incomes: [CategoryTotal]
        let transactions: [Transaction]
        var isEmpty: Bool { transactions.isEmpty }
        var incomeText: String { "+" + MoneyFormatter.string(from: income) }
        var expenseText: String { "−" + MoneyFormatter.string(from: expense) }
        var differenceText: String { (difference >= 0 ? "+" : "") + MoneyFormatter.string(from: difference) }

        func rows(for kind: TransactionKind) -> [CategoryTotal] { kind == .income ? incomes : kind == .expense ? expenses : [] }
        func transactions(for key: CategoryKey) -> [Transaction] {
            guard key.kind != .transfer else { return [] }
            return transactions.filter { $0.kindRaw == key.kind.rawValue && $0.category?.id == key.categoryID }
        }
    }

    static func report(year: Int, month: Int, transactions: [Transaction]) throws -> Report {
        try report(month: ReportingMonth(year: year, month: month), transactions: transactions)
    }

    static func report(month: ReportingMonth, transactions: [Transaction]) throws -> Report {
        let interval = month.interval
        let monthly = transactions.filter { $0.date >= interval.start && $0.date < interval.end }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
        // The one aggregation implementation lives in BalanceCalculator.
        // Include legacy missing-category rows; write validation and the
        // calculator's default validation mode remain strict.
        let totals = try BalanceCalculator.flowTotals(transactions: monthly, allowMissingCategory: true)
        let (difference, overflow) = totals.income.subtractingReportingOverflow(totals.expense)
        guard !overflow else { throw BalanceCalculator.CalculationError.overflow }
        var categories: [UUID: Category] = [:]
        for transaction in monthly {
            if let category = transaction.category { categories[category.id] = category }
        }
        return Report(month: month, income: totals.income, expense: totals.expense, difference: difference,
                      expenses: rows(totals.expenseByCategory, uncategorized: totals.uncategorizedExpense,
                                     total: totals.expense, kind: .expense, categories: categories),
                      incomes: rows(totals.incomeByCategory, uncategorized: totals.uncategorizedIncome,
                                    total: totals.income, kind: .income, categories: categories), transactions: monthly)
    }

    struct DailyTotal: Identifiable, Equatable {
        var id: Int { day }
        let day: Int
        let expense: Int64
        var plotValue: Double { StatsService.plotValue(expense) }
    }

    // Display only: chart coordinates never flow back into money arithmetic.
    static func plotValue(_ amount: Int64) -> Double { Double(amount) }

    static func dailyExpenses(month: ReportingMonth, transactions: [Transaction]) throws -> [DailyTotal] {
        let calendar = LocalCalendar.calendar
        let count = calendar.range(of: .day, in: .month, for: month.interval.start)!.count
        return try (1...count).map { day in
            let start = calendar.date(byAdding: .day, value: day - 1, to: month.interval.start)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return DailyTotal(day: day, expense: try BalanceCalculator.flowTotals(transactions: transactions,
                during: DateInterval(start: start, end: end), allowMissingCategory: true).expense)
        }
    }

    static func dailyAllowance(limit: Int64, month: ReportingMonth) -> Int64 {
        limit / Int64(LocalCalendar.calendar.range(of: .day, in: .month, for: month.interval.start)!.count)
    }

    static func expenseSlices(_ report: Report, top: Int = 5) -> [CategoryTotal] {
        let count = max(0, top)
        guard report.expenses.count > count else { return report.expenses }
        var slices = Array(report.expenses.prefix(count))
        var remainder = report.expense
        for slice in slices { remainder -= slice.amount }
        slices.append(CategoryTotal(key: CategoryKey(kind: .expense, categoryID: nil, isOther: true),
            name: "Khác", icon: "ellipsis.circle", amount: remainder,
            percentageTenths: StatsPercentage.tenths(amount: remainder, total: report.expense)))
        return slices
    }

    private static func rows(_ amounts: [UUID: Int64], uncategorized: Int64, total: Int64,
                             kind: TransactionKind, categories: [UUID: Category]) -> [CategoryTotal] {
        var rows = amounts.compactMap { id, amount -> CategoryTotal? in
            guard amount > 0 else { return nil }
            return CategoryTotal(key: CategoryKey(kind: kind, categoryID: id), name: categories[id]?.name ?? "Không có danh mục",
                                 icon: categories[id]?.icon ?? "questionmark.circle", amount: amount,
                                 percentageTenths: StatsPercentage.tenths(amount: amount, total: total))
        }
        if uncategorized > 0 {
            rows.append(CategoryTotal(key: CategoryKey(kind: kind, categoryID: nil), name: "Không có danh mục",
                                      icon: "questionmark.circle", amount: uncategorized,
                                      percentageTenths: StatsPercentage.tenths(amount: uncategorized, total: total)))
        }
        return rows.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return ($0.key.categoryID?.uuidString ?? "") < ($1.key.categoryID?.uuidString ?? "")
        }
    }
}
