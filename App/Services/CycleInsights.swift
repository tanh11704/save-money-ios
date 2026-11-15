import Foundation

// MARK: - Flexible daily allowance

extension StatsService {
    /// "How much may I still spend today": what is left of the total budget at the start of
    /// today, spread over the days left in the cycle (today included). Unlike `dailyAllowance`
    /// it adapts — overspending yesterday lowers today's figure, saving raises it.
    struct FlexibleAllowance: Equatable {
        let limit: Int64
        let spentBeforeToday: Int64
        let spentToday: Int64
        /// Days left in the cycle, today included; at least 1.
        let daysLeft: Int
        /// Budget left at the start of today ÷ days left; 0 once the budget is used up.
        let perDay: Int64
        /// `perDay − spentToday`; negative when today already went over.
        let leftToday: Int64
        /// Budget left in the whole cycle after today's spending; negative when over.
        let leftInCycle: Int64
    }

    /// Nil when `now` is outside `month`: the figure only makes sense for the running cycle.
    static func flexibleAllowance(limit: Int64, month: ReportingMonth, transactions: [Transaction], now: Date = Date()) throws -> FlexibleAllowance? {
        let interval = month.interval
        guard limit > 0, now >= interval.start, now < interval.end else { return nil }
        let calendar = LocalCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let before = try BalanceCalculator.flowTotals(transactions: transactions, during: DateInterval(start: interval.start, end: today),
                                                      allowMissingCategory: true).expense
        let todaySpent = try BalanceCalculator.flowTotals(transactions: transactions, during: DateInterval(start: today, end: tomorrow),
                                                          allowMissingCategory: true).expense
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: interval.end).day!)
        let remaining = limit.subtractingReportingOverflow(before)
        let cycleLeft = remaining.partialValue.subtractingReportingOverflow(todaySpent)
        guard !remaining.overflow, !cycleLeft.overflow else { throw BalanceCalculator.CalculationError.overflow }
        let perDay = max(0, remaining.partialValue) / Int64(daysLeft)
        let leftToday = perDay.subtractingReportingOverflow(todaySpent)
        guard !leftToday.overflow else { throw BalanceCalculator.CalculationError.overflow }
        return FlexibleAllowance(limit: limit, spentBeforeToday: before, spentToday: todaySpent, daysLeft: daysLeft,
                                 perDay: perDay, leftToday: leftToday.partialValue, leftInCycle: cycleLeft.partialValue)
    }
}

// MARK: - End-of-cycle summary

/// A look back at a finished (payday) month: totals, savings, top categories and budgets.
struct CycleSummary {
    let month: ReportingMonth
    let report: StatsService.Report
    /// Against the cycle before; nil when that one cannot be computed.
    let comparison: StatsService.Comparison?
    let topExpenses: [StatsService.CategoryTotal]
    let budgets: [BudgetService.Progress]

    var saved: Int64 { report.difference }
    /// Share of income kept, in tenths of a percent; nil without income.
    var savedRateTenths: Int? {
        guard report.income > 0 else { return nil }
        return StatsPercentage.tenths(amount: max(0, min(report.difference, report.income)), total: report.income)
    }
    var overBudget: [BudgetService.Progress] { budgets.filter { $0.level == .over } }
    var totalBudget: BudgetService.Progress? { budgets.first { $0.scope == .total } }

    static func make(month: ReportingMonth, transactions: [Transaction], rules: [BudgetRule]) throws -> CycleSummary {
        let report = try StatsService.report(month: month, transactions: transactions)
        // `now` after the cycle: compare whole cycles, not elapsed days.
        let comparison = try? StatsService.comparison(month: month, now: month.interval.end, transactions: transactions)
        return CycleSummary(month: month, report: report, comparison: comparison, topExpenses: Array(report.expenses.prefix(3)),
                            budgets: try BudgetService.progress(month: month, rules: rules, transactions: transactions))
    }
}

/// Shows the summary once, on the first launch after a cycle ends.
enum CycleSummaryTracker {
    static let lastShownKey = "SaveMoney.cycleSummary.lastShown"

    static func identifier(_ month: ReportingMonth) -> String { String(format: "%04d-%02d", month.year, month.month) }

    /// The cycle that just ended, if it had transactions and its summary has not been shown yet.
    static func pending(now: Date = Date(), transactions: [Transaction], defaults: UserDefaults = .standard) -> ReportingMonth? {
        guard let previous = ReportingMonth(containing: now).previous,
              defaults.string(forKey: lastShownKey) != identifier(previous) else { return nil }
        let interval = previous.interval
        guard transactions.contains(where: { $0.date >= interval.start && $0.date < interval.end }) else { return nil }
        return previous
    }

    static func markShown(_ month: ReportingMonth, defaults: UserDefaults = .standard) {
        defaults.set(identifier(month), forKey: lastShownKey)
    }
}

// MARK: - Widget snapshot

extension WidgetSnapshot {
    /// Builds the widget summary for the running cycle. Amounts are omitted unless `showsAmounts`.
    static func make(transactions: [Transaction], totalBalance: Int64, rules: [BudgetRule],
                     showsAmounts: Bool, now: Date = Date()) -> WidgetSnapshot {
        let calendar = LocalCalendar.calendar
        let month = ReportingMonth(containing: now)
        let today = calendar.startOfDay(for: now)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: month.interval.end).day!)
        var snapshot = WidgetSnapshot(generatedAt: now, day: today, cycleName: month.shortName, daysLeft: daysLeft, showsAmounts: showsAmounts)
        let total = (try? BudgetService.progress(month: month, rules: rules, transactions: transactions))?.first { $0.scope == .total }
        if let total {
            snapshot.budgetFraction = Double(total.spent) / Double(total.limit)
            snapshot.budgetLevel = total.level.rawValue
        }
        guard showsAmounts else { return snapshot }
        snapshot.totalBalance = totalBalance
        if let total {
            snapshot.cycleSpent = total.spent
            snapshot.cycleLimit = total.limit
            if let allowance = try? StatsService.flexibleAllowance(limit: total.limit, month: month, transactions: transactions, now: now) {
                snapshot.todayLeft = allowance.leftToday
                snapshot.perDay = allowance.perDay
                snapshot.spentToday = allowance.spentToday
            }
        }
        if snapshot.spentToday == nil {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            snapshot.spentToday = try? BalanceCalculator.flowTotals(transactions: transactions, during: DateInterval(start: today, end: tomorrow),
                                                                    allowMissingCategory: true).expense
        }
        return snapshot
    }
}
