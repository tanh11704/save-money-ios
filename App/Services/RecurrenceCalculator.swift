import Foundation

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case daily, weekly, monthly, yearly
    var title: String {
        switch self { case .daily: return "ngày"; case .weekly: return "tuần"; case .monthly: return "tháng"; case .yearly: return "năm" }
    }
}

struct RecurrenceCalculator {
    static func occurrences(start: Date, frequency: RecurrenceFrequency, interval: Int,
                            end: Date?, after: Date?, through: Date, limit: Int = 400) -> [Date] {
        guard interval >= 1, limit > 0 else { return [] }
        let calendar = LocalCalendar.calendar, start = LocalCalendar.calendar.startOfDay(for: start)
        let through = calendar.startOfDay(for: through)
        let end = end.map { calendar.startOfDay(for: $0) }
        guard end.map({ $0 >= start }) ?? true else { return [] }
        let upper = min(through, end ?? through)
        guard upper >= start, after.map({ $0 < upper }) ?? true else { return [] }
        let component: Calendar.Component
        let step: Int
        switch frequency {
        case .daily: component = .day; step = interval
        case .weekly:
            let product = interval.multipliedReportingOverflow(by: 7)
            guard !product.overflow else { return after.map({ start > $0 }) ?? true ? [start] : [] }
            component = .day; step = product.partialValue
        case .monthly: component = .month; step = interval
        case .yearly: component = .year; step = interval
        }
        // Jump near the cursor instead of walking every historical occurrence.
        let distance = after.map { calendar.dateComponents([component], from: start, to: $0).value(for: component) ?? 0 } ?? 0
        let horizon = (calendar.dateComponents([component], from: start, to: upper).value(for: component) ?? 0) + 1
        var index = max(0, distance / step - 1), dates: [Date] = []
        while dates.count < limit {
            let offset = index.multipliedReportingOverflow(by: step)
            guard !offset.overflow, offset.partialValue <= horizon, let date = calendar.date(byAdding: component, value: offset.partialValue, to: start), date <= upper else { break }
            if after.map({ date > $0 }) ?? true { dates.append(date) }
            let next = index.addingReportingOverflow(1)
            guard !next.overflow else { break }
            index = next.partialValue
        }
        return dates
    }

    static func key(ruleID: UUID, occurrence: Date) -> String {
        let parts = LocalCalendar.calendar.dateComponents([.year, .month, .day], from: occurrence)
        return ruleID.uuidString + "." + String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
    }
}
