import Foundation

struct TransactionGrouping {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let transactions: [Transaction]
    }

    static func group(_ transactions: [Transaction]) -> [Day] {
        let groups = Dictionary(grouping: transactions) { LocalCalendar.calendar.startOfDay(for: $0.date) }
        return groups.map { date, transactions in
            Day(date: date, transactions: transactions.sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            })
        }.sorted { $0.date > $1.date }
    }

    static func title(for day: Date, now: Date = Date()) -> String {
        let calendar = LocalCalendar.calendar
        if calendar.isDate(day, inSameDayAs: now) { return "Hôm nay" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Hôm qua"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, dd/MM/yyyy"
        return formatter.string(from: day)
    }
}
