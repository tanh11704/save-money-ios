import Foundation

extension StatsService {
    struct Comparison: Equatable {
        struct Delta: Equatable {
            let current: Int64
            let previous: Int64
            let difference: Int64
            let percentageTenths: Int?
            var text: String {
                let direction = difference > 0 ? "Tăng" : difference < 0 ? "Giảm" : "Không đổi"
                let percentage = percentageTenths.map { StatsPercentage.text(tenths: abs($0)) } ?? (current > 0 ? "Mới" : "")
                let amount = (difference > 0 ? "+" : "") + MoneyFormatter.string(from: difference)
                return "\(direction) \(percentage) (\(amount))"
            }
        }
        let currentRange: DateInterval
        let previousRange: DateInterval
        let income: Delta
        let expense: Delta
        let expenseByCategory: [UUID?: Delta]
        let label: String
        var balance: Delta? {
            let current = income.current.subtractingReportingOverflow(expense.current)
            let previous = income.previous.subtractingReportingOverflow(expense.previous)
            guard !current.overflow, !previous.overflow else { return nil }
            return try? StatsService.delta(current: current.partialValue, previous: previous.partialValue)
        }
    }

    static func comparison(month: ReportingMonth, now: Date, transactions: [Transaction]) throws -> Comparison {
        guard let previous = month.previous else { throw ReportingMonth.MonthError.invalidMonth }
        let calendar = LocalCalendar.calendar
        let isCurrent = month == ReportingMonth(containing: now)
        let day = calendar.component(.day, from: now)
        let previousDays = calendar.range(of: .day, in: .month, for: previous.interval.start)!.count
        let currentEnd = isCurrent ? calendar.date(byAdding: .day, value: day, to: month.interval.start)! : month.interval.end
        let previousEnd = isCurrent ? calendar.date(byAdding: .day, value: min(day, previousDays), to: previous.interval.start)! : previous.interval.end
        let currentRange = DateInterval(start: month.interval.start, end: currentEnd)
        let previousRange = DateInterval(start: previous.interval.start, end: previousEnd)
        let a = try BalanceCalculator.flowTotals(transactions: transactions, during: currentRange, allowMissingCategory: true)
        let b = try BalanceCalculator.flowTotals(transactions: transactions, during: previousRange, allowMissingCategory: true)
        var currentCategories = Dictionary(uniqueKeysWithValues: a.expenseByCategory.map { (Optional($0.key), $0.value) })
        var previousCategories = Dictionary(uniqueKeysWithValues: b.expenseByCategory.map { (Optional($0.key), $0.value) })
        if a.uncategorizedExpense > 0 { currentCategories[nil] = a.uncategorizedExpense }
        if b.uncategorizedExpense > 0 { previousCategories[nil] = b.uncategorizedExpense }
        var categories: [UUID?: Comparison.Delta] = [:]
        for key in Set(currentCategories.keys).union(previousCategories.keys) {
            categories[key] = try delta(current: currentCategories[key, default: 0], previous: previousCategories[key, default: 0])
        }
        return Comparison(currentRange: currentRange, previousRange: previousRange,
            income: try delta(current: a.income, previous: b.income), expense: try delta(current: a.expense, previous: b.expense),
            expenseByCategory: categories,
            label: isCurrent ? "so với 1–\(min(day, previousDays))/\(previous.month)" : "so với tháng \(previous.month)/\(previous.year)")
    }

    private static func delta(current: Int64, previous: Int64) throws -> Comparison.Delta {
        let difference = current.subtractingReportingOverflow(previous)
        guard !difference.overflow else { throw BalanceCalculator.CalculationError.overflow }
        var percentage: Int?
        if previous != 0 {
            var ratio = Decimal(difference.partialValue) * 1_000 / Decimal(previous), rounded = Decimal()
            NSDecimalRound(&rounded, &ratio, 0, .plain)
            percentage = NSDecimalNumber(decimal: min(9_999, max(-9_999, rounded))).intValue
        }
        return Comparison.Delta(current: current, previous: previous, difference: difference.partialValue, percentageTenths: percentage)
    }
}
