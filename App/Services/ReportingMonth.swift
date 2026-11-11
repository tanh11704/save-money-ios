import Foundation

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

    init(containing date: Date = Date()) {
        let parts = LocalCalendar.calendar.dateComponents([.year, .month], from: date)
        year = parts.year!
        month = parts.month!
    }

    var interval: DateInterval {
        let start = LocalCalendar.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return LocalCalendar.month(containing: start)
    }
    var title: String { "Tháng \(month)/\(year)" }
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

/// A statistics window: a Monday–Sunday week or a calendar month, both in Asia/Saigon.
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
        case .month: interval = LocalCalendar.month(containing: date)
        }
    }

    init(month: ReportingMonth) {
        kind = .month
        interval = month.interval
    }

    /// The month containing the first day; for a week spanning two months this is the earlier one.
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
