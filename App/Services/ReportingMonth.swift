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
