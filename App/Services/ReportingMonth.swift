import Foundation

/// The day a "month" starts on, e.g. payday. 1 means calendar months.
/// A cycle is named after the calendar month it mostly covers: a start day of
/// 1–15 names it after the month it starts in (5/11–4/12 is "tháng 11"), a
/// start day of 16–31 after the month it ends in (25/10–24/11 is "tháng 11").
/// Days past the end of a short month clamp to its last day (31 → 28/2).
enum MonthCycle {
    static let startDayKey = "SaveMoney.monthStartDay"
    static let validDays = 1...31
    static var defaults: UserDefaults = .standard

    static var startDay: Int {
        get {
            let value = defaults.integer(forKey: startDayKey)
            return validDays.contains(value) ? value : 1
        }
        set { defaults.set(validDays.contains(newValue) ? newValue : 1, forKey: startDayKey) }
    }

    static var isCalendarMonth: Bool { startDay == 1 }

    /// Months between a cycle's name and the calendar month it starts in.
    static func startMonthOffset(startDay: Int) -> Int { startDay > 15 ? -1 : 0 }

    /// Local midnight on which the cycle named (year, month) starts.
    static func start(year: Int, month: Int, startDay: Int = startDay) -> Date {
        let calendar = LocalCalendar.calendar
        let named = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let first = calendar.date(byAdding: .month, value: startMonthOffset(startDay: startDay), to: named)!
        let days = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(byAdding: .day, value: min(startDay, days) - 1, to: first)!
    }
}

struct ReportingMonth: Hashable, Comparable {
    enum MonthError: LocalizedError {
        case invalidMonth
        var errorDescription: String? { "Tháng hoặc năm không hợp lệ." }
    }
    let year: Int
    let month: Int

    init(year: Int, month: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month) else { throw MonthError.invalidMonth }
        self.year = year
        self.month = month
    }

    /// The cycle containing `date` under the current `MonthCycle.startDay`.
    init(containing date: Date = Date()) {
        let startDay = MonthCycle.startDay
        let parts = LocalCalendar.calendar.dateComponents([.year, .month], from: date)
        // Candidate: the cycle that starts in this calendar month; else the one before.
        var index = parts.year! * 12 + parts.month! - 1 - MonthCycle.startMonthOffset(startDay: startDay)
        if date < MonthCycle.start(year: index / 12, month: index % 12 + 1, startDay: startDay) { index -= 1 }
        year = index / 12
        month = index % 12 + 1
    }

    var interval: DateInterval {
        let startDay = MonthCycle.startDay
        let start = MonthCycle.start(year: year, month: month, startDay: startDay)
        let end = month == 12
            ? MonthCycle.start(year: year + 1, month: 1, startDay: startDay)
            : MonthCycle.start(year: year, month: month + 1, startDay: startDay)
        return DateInterval(start: start, end: end)
    }
    var dayCount: Int { LocalCalendar.calendar.dateComponents([.day], from: interval.start, to: interval.end).day! }
    var lastDay: Date { LocalCalendar.calendar.date(byAdding: .day, value: -1, to: interval.end)! }
    /// "25/10–24/11"
    var rangeText: String { "\(StatsPeriod.dayMonth(interval.start))–\(StatsPeriod.dayMonth(lastDay))" }
    /// "Tháng 11/2026", or "Tháng 11/2026 (25/10–24/11)" for a payday cycle.
    var title: String {
        MonthCycle.isCalendarMonth ? "Tháng \(month)/\(year)" : "Tháng \(month)/\(year) (\(rangeText))"
    }
    /// In-sentence form: "tháng 11" or "tháng 11 (25/10–24/11)".
    var shortName: String {
        MonthCycle.isCalendarMonth ? "tháng \(month)" : "tháng \(month) (\(rangeText))"
    }
    var previous: ReportingMonth? {
        try? ReportingMonth(year: month == 1 ? year - 1 : year, month: month == 1 ? 12 : month - 1)
    }
    var next: ReportingMonth? {
        try? ReportingMonth(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1)
    }
    func next(upTo current: ReportingMonth) -> ReportingMonth? {
        guard let next, next <= current else { return nil }
        return next
    }
    func clamped(to current: ReportingMonth) -> ReportingMonth { min(self, current) }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.year == rhs.year ? lhs.month < rhs.month : lhs.year < rhs.year
    }
}

/// Display-only tenths of a percent. Decimal never flows back into money.
struct StatsPercentage {
    static func tenths(amount: Int64, total: Int64) -> Int {
        guard amount >= 0, total > 0, amount <= total else { return 0 }
        var ratio = Decimal(amount) * 1_000 / Decimal(total)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &ratio, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
    static func text(tenths: Int) -> String { "\(tenths / 10),\(tenths % 10)%" }
}

enum StatsPeriodKind: String, CaseIterable, Hashable {
    case week, month
    var title: String { self == .week ? "Tuần" : "Tháng" }
}

/// A statistics window: a Monday–Sunday week or a (payday) month cycle, both in Asia/Saigon.
/// The interval end is exclusive, matching `ReportingMonth.interval`.
struct StatsPeriod: Hashable, Comparable {
    let kind: StatsPeriodKind
    let interval: DateInterval

    /// Vietnamese weeks start on Monday (Thứ Hai) regardless of the device locale.
    static var weekCalendar: Calendar {
        var calendar = LocalCalendar.calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    init(kind: StatsPeriodKind, containing date: Date = Date()) {
        self.kind = kind
        switch kind {
        case .week: interval = Self.weekCalendar.dateInterval(of: .weekOfYear, for: date)!
        case .month: interval = ReportingMonth(containing: date).interval
        }
    }

    init(month: ReportingMonth) {
        kind = .month
        interval = month.interval
    }

    /// The month cycle containing the first day; for a week spanning two cycles this is the earlier one.
    var month: ReportingMonth { ReportingMonth(containing: interval.start) }
    var dayCount: Int { LocalCalendar.calendar.dateComponents([.day], from: interval.start, to: interval.end).day! }
    var lastDay: Date { LocalCalendar.calendar.date(byAdding: .day, value: -1, to: interval.end)! }
    var previous: StatsPeriod { StatsPeriod(kind: kind, containing: interval.start.addingTimeInterval(-1)) }
    var next: StatsPeriod { StatsPeriod(kind: kind, containing: interval.end) }

    func next(upTo current: StatsPeriod) -> StatsPeriod? {
        let candidate = next
        return candidate <= current ? candidate : nil
    }

    func contains(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

    /// `count` periods ending with this one, oldest first.
    func trailing(_ count: Int) -> [StatsPeriod] {
        guard count > 0 else { return [] }
        var periods = [self]
        while periods.count < count { periods.insert(periods[0].previous, at: 0) }
        return periods
    }

    var title: String {
        switch kind {
        case .month: return month.title
        case .week: return "Tuần \(Self.dayMonth(interval.start)) – \(Self.dayMonth(lastDay))"
        }
    }

    /// Axis label for trend charts: "T11" (or "T1/27" in January) for months, "9/11" for weeks.
    var shortTitle: String {
        switch kind {
        case .month: return month.month == 1 ? "T1/\(String(month.year % 100))" : "T\(month.month)"
        case .week: return Self.dayMonth(interval.start)
        }
    }

    static func dayMonth(_ date: Date) -> String {
        let parts = LocalCalendar.calendar.dateComponents([.day, .month], from: date)
        return "\(parts.day!)/\(parts.month!)"
    }

    /// "T2" … "T7", "CN" for a date, independent of device locale.
    static func weekdayLabel(_ date: Date) -> String {
        let weekday = LocalCalendar.calendar.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? "CN" : "T\(weekday)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.interval.start < rhs.interval.start }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
