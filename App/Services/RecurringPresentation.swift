import Foundation

struct RecurringPresentation {
    struct Preview {
        let upcoming: String
        let catchUp: String?
    }
    static func schedule(_ rule: RecurringRule) -> String {
        guard let frequency = RecurrenceFrequency(rawValue: rule.frequencyRaw) else { return "Chu kỳ không hợp lệ" }
        let base = rule.interval == 1 ? "Hằng \(frequency.title)" : "Mỗi \(rule.interval) \(frequency.title)"
        if frequency == .monthly { return base + ", ngày \(LocalCalendar.calendar.component(.day, from: rule.startDate))" }
        return base
    }
    static func preview(_ draft: RecurringDraft, generatedThrough: Date?, now: Date = Date()) -> Preview {
        let ceiling = LocalCalendar.calendar.date(from: DateComponents(year: 9999, month: 12, day: 31))!
        let today = LocalCalendar.calendar.startOfDay(for: now)
        let after = max(generatedThrough ?? .distantPast, today.addingTimeInterval(-1))
        let next = RecurrenceCalculator.occurrences(start: draft.startDate, frequency: draft.frequency, interval: draft.interval,
            end: draft.endDate, after: after, through: ceiling, limit: 3)
        let due = RecurrenceCalculator.occurrences(start: draft.startDate, frequency: draft.frequency, interval: draft.interval,
            end: draft.endDate, after: generatedThrough, through: now, limit: 401)
        let formatter = DateFormatter(); formatter.calendar = LocalCalendar.calendar
        formatter.timeZone = LocalCalendar.calendar.timeZone; formatter.locale = Locale(identifier: "vi_VN"); formatter.dateFormat = "dd/MM/yyyy"
        let upcoming = next.isEmpty ? "Không còn lần đến hạn." : "Các lần tới: " + next.map(formatter.string).joined(separator: ", ")
        var catchUp: String?
        if let first = due.first, let last = due.prefix(400).last {
            catchUp = "Sẽ tạo ngay \(min(due.count, 400)) giao dịch từ \(formatter.string(from: first)) đến \(formatter.string(from: last))."
            if due.count > 400 { catchUp! += " Còn lại sẽ tạo ở lần mở app sau." }
        }
        return Preview(upcoming: upcoming, catchUp: catchUp)
    }
    static func next(_ rule: RecurringRule, now: Date = Date()) -> String {
        guard let draft = rule.draft else { return "Cần sửa quy tắc." }
        let ceiling = LocalCalendar.calendar.date(from: DateComponents(year: 9999, month: 12, day: 31))!
        let dates = RecurrenceCalculator.occurrences(start: draft.startDate, frequency: draft.frequency, interval: draft.interval,
            end: draft.endDate, after: rule.generatedThrough, through: ceiling, limit: 1)
        return dates.first.map { "Lần tới: " + TransactionPresentation.shortDate($0) } ?? "Đã kết thúc"
    }
}
