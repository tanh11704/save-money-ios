import Foundation

// MARK: - Personal preferences (UserDefaults; no schema or backup change)

/// The wallet new expenses and incomes start from. Falls back to the last used wallet when unset or archived.
enum MainWallet {
    static let key = "SaveMoney.mainWalletID"
    static var defaults: UserDefaults = .standard

    static var id: UUID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { if let newValue { defaults.set(newValue.uuidString, forKey: key) } else { defaults.removeObject(forKey: key) } }
    }
}

/// Colour of a wallet card, as an index into the view layer's palette. Nil means "by wallet kind".
enum WalletAppearance {
    static let paletteCount = 8
    static func key(_ id: UUID) -> String { "SaveMoney.walletColor.\(id.uuidString)" }

    static func colorIndex(for id: UUID, defaults: UserDefaults = .standard) -> Int? {
        guard defaults.object(forKey: key(id)) != nil else { return nil }
        let value = defaults.integer(forKey: key(id))
        return (0..<paletteCount).contains(value) ? value : nil
    }

    static func setColorIndex(_ index: Int?, for id: UUID, defaults: UserDefaults = .standard) {
        if let index, (0..<paletteCount).contains(index) { defaults.set(index, forKey: key(id)) } else { defaults.removeObject(forKey: key(id)) }
    }
}

enum AppearanceSettings {
    static let accentKey = "SaveMoney.accent"
    static let startScreenKey = "SaveMoney.startScreen"
    static let dailyReminderKey = "SaveMoney.dailyReminder"

    enum StartScreen: String, CaseIterable, Identifiable {
        case overview, add
        var id: String { rawValue }
        var title: String { self == .overview ? "Tổng quan" : "Thêm giao dịch" }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case standard, teal, blue, indigo, pink, orange
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: return "Mặc định"
            case .teal: return "Xanh ngọc"
            case .blue: return "Xanh dương"
            case .indigo: return "Chàm"
            case .pink: return "Hồng"
            case .orange: return "Cam"
            }
        }
    }
}

// MARK: - Budget pace

/// Compares spending with where an even pace would be today: "Chi nhanh hơn kế hoạch 620k".
struct BudgetPace: Equatable {
    enum Status { case ahead, onTrack, behind }
    let spent: Int64
    let limit: Int64
    /// Days elapsed in the cycle (today included) and the cycle length.
    let elapsedDays: Int
    let dayCount: Int
    /// Spending an even pace allows by the end of today.
    let expected: Int64
    /// `spent − expected`; positive means spending faster than planned.
    let difference: Int64

    /// Display only.
    var elapsedFraction: Double { dayCount > 0 ? Double(elapsedDays) / Double(dayCount) : 0 }
    var spentFraction: Double { limit > 0 ? Double(spent) / Double(limit) : 0 }

    /// Within 5% of the limit counts as on track.
    var status: Status {
        let tolerance = limit / 20
        if difference > tolerance { return .ahead }
        if difference < -tolerance { return .behind }
        return .onTrack
    }

    var text: String {
        switch status {
        case .ahead: return "Chi nhanh hơn kế hoạch \(MoneyFormatter.compact(difference))"
        case .behind: return "Chậm hơn kế hoạch \(MoneyFormatter.compact(-difference)) · tốt lắm!"
        case .onTrack: return "Đúng nhịp kế hoạch"
        }
    }

    /// Nil outside the cycle or without a positive limit.
    /// Fixed costs are expected in full once paid; only the flexible rest of the limit is expected to
    /// build up evenly, so paying the rent on day 1 does not read as "spending too fast".
    static func make(spent: Int64, limit: Int64, month: ReportingMonth, fixed: FixedCosts.Totals = .zero,
                     now: Date = Date()) -> BudgetPace? {
        let interval = month.interval
        guard limit > 0, now >= interval.start, now < interval.end else { return nil }
        let calendar = LocalCalendar.calendar
        let dayCount = month.dayCount
        let elapsed = min(dayCount, calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day! + 1)
        let flexible = limit - min(limit, max(0, fixed.total))
        let paid = max(0, fixed.spent)
        // flexible ≤ limit ≤ 999.999.999.999 and days ≤ 31, so the product cannot overflow Int64.
        let even = flexible * Int64(elapsed) / Int64(dayCount)
        let expected = paid.addingReportingOverflow(even).overflow ? Int64.max : paid + even
        return BudgetPace(spent: spent, limit: limit, elapsedDays: elapsed, dayCount: dayCount, expected: expected, difference: spent - expected)
    }
}

// MARK: - Logging streak

enum LoggingStreak {
    /// Consecutive days with at least one transaction, ending today, or yesterday when nothing is logged today yet.
    static func days(transactions: [Transaction], now: Date = Date()) -> Int {
        let calendar = LocalCalendar.calendar
        let logged = Set(transactions.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !logged.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while logged.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func hasLoggedToday(transactions: [Transaction], now: Date = Date()) -> Bool {
        transactions.contains { LocalCalendar.calendar.isDate($0.date, inSameDayAs: now) }
    }
}

// MARK: - Statistics insights

/// Short sentences that explain a report: biggest category change, weekend share, top day, savings.
struct StatsInsight: Identifiable, Equatable {
    var id: String { text }
    let icon: String
    let text: String

    static func make(report: StatsService.Report, comparison: StatsService.Comparison?, kind: StatsPeriodKind) -> [StatsInsight] {
        var insights: [StatsInsight] = []
        let names = Dictionary(report.expenses.map { ($0.key.categoryID, $0.name) }, uniquingKeysWith: { first, _ in first })
        let unit = kind == .week ? "tuần trước" : "kỳ trước"
        if let comparison {
            let increases = comparison.expenseByCategory.filter { $0.value.difference > 0 && names[$0.key] != nil }
            if let (id, delta) = increases.max(by: { $0.value.difference < $1.value.difference }), let name = names[id] {
                let percent = delta.percentageTenths.map { " " + StatsPercentage.text(tenths: $0) } ?? ""
                insights.append(StatsInsight(icon: "arrow.up.right.circle.fill", text: "\(name) tăng\(percent) (+\(MoneyFormatter.compact(delta.difference))) so với \(unit)"))
            }
            if comparison.expense.previous > 0, comparison.expense.difference < 0 {
                insights.append(StatsInsight(icon: "arrow.down.right.circle.fill", text: "Tổng chi giảm \(MoneyFormatter.compact(-comparison.expense.difference)) so với \(unit)"))
            }
        }
        let calendar = LocalCalendar.calendar
        let expenses = report.transactions.filter { $0.kindRaw == TransactionKind.expense.rawValue }
        if kind == .month, report.expense > 0 {
            let weekend = saturatingSum(expenses.filter { [1, 7].contains(calendar.component(.weekday, from: $0.date)) }.map(\.amount))
            let tenths = StatsPercentage.tenths(amount: min(weekend, report.expense), total: report.expense)
            if tenths >= 350 { insights.append(StatsInsight(icon: "calendar", text: "Cuối tuần chiếm \(StatsPercentage.text(tenths: tenths)) chi tiêu")) }
        }
        let byDay = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.date) }.mapValues { saturatingSum($0.map(\.amount)) }
        if byDay.count > 1, let top = byDay.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
            insights.append(StatsInsight(icon: "flame.fill", text: "Ngày chi nhiều nhất: \(StatsPeriod.dayMonth(top.key)) (\(MoneyFormatter.compact(top.value)))"))
        }
        if report.income > 0, report.difference > 0 {
            let tenths = StatsPercentage.tenths(amount: min(report.difference, report.income), total: report.income)
            insights.append(StatsInsight(icon: "leaf.fill", text: "Để dành \(StatsPercentage.text(tenths: tenths)) thu nhập"))
        }
        return Array(insights.prefix(3))
    }

    private static func saturatingSum(_ amounts: [Int64]) -> Int64 {
        amounts.reduce(Int64(0)) { total, amount in
            let sum = total.addingReportingOverflow(amount)
            return sum.overflow ? .max : sum.partialValue
        }
    }
}

// MARK: - Spending heatmap

enum SpendingHeatmap {
    /// Expense per local day in `interval` (transfers and income excluded).
    static func dailyExpenses(transactions: [Transaction], in interval: DateInterval) -> [Date: Int64] {
        let calendar = LocalCalendar.calendar
        var totals: [Date: Int64] = [:]
        for transaction in transactions where transaction.kindRaw == TransactionKind.expense.rawValue
            && transaction.date >= interval.start && transaction.date < interval.end {
            let day = calendar.startOfDay(for: transaction.date)
            let sum = totals[day, default: 0].addingReportingOverflow(transaction.amount)
            totals[day] = sum.overflow ? .max : sum.partialValue
        }
        return totals
    }

    /// 0 (no spending) … 4 (the top of the range), scaled to the period's largest day.
    static func level(_ amount: Int64, maximum: Int64) -> Int {
        guard amount > 0, maximum > 0 else { return 0 }
        let ratio = Double(amount) / Double(maximum)
        return ratio > 0.75 ? 4 : ratio > 0.5 ? 3 : ratio > 0.25 ? 2 : 1
    }
}

// MARK: - Upcoming items

struct UpcomingItem: Identifiable, Equatable {
    enum Kind { case recurring, installment, cardDue }
    let id: String
    let kind: Kind
    let title: String
    let date: Date
    let amount: Int64?
}
