import Foundation

/// A device's locale or time zone must never move a transaction to another month.
struct LocalCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Saigon")!
        return calendar
    }

    static func month(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }
}
