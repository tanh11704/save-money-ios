import Foundation

struct CSVExporter {
    enum ExportError: LocalizedError {
        case invalidRange
        var errorDescription: String? { "Ngày kết thúc không được trước ngày bắt đầu." }
    }
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveMoneyCSV", isDirectory: true)
    static func range(from: Date, to: Date) throws -> DateInterval {
        let calendar = LocalCalendar.calendar, start = LocalCalendar.calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)), end > start else { throw ExportError.invalidRange }
        return DateInterval(start: start, end: end)
    }
    static func csv(transactions: [Transaction], from: Date, to: Date) throws -> Data {
        let range = try range(from: from, to: to)
        let records = transactions.filter { $0.date >= range.start && $0.date < range.end }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        let date = formatter("dd/MM/yyyy"), time = formatter("HH:mm")
        var rows = [["Ngày", "Giờ", "Loại", "Số tiền", "Số tiền có dấu", "Danh mục", "Ví", "Ví đích", "Ghi chú", "Định kỳ", "ID"]]
        let debtLabels = try DebtPresentation.labels(transactions: transactions)
        for t in records {
            guard let kind = TransactionKind(rawValue: t.kindRaw), t.amount > 0 else { throw BalanceCalculator.CalculationError.invalidTransaction(t.id) }
            rows.append([date.string(from: t.date), time.string(from: t.date), text(debtLabels[t.id]?.title ?? TransactionPresentation.kindTitle(kind)), String(t.amount),
                kind == .transfer ? "0" : String(kind == .expense ? -t.amount : t.amount),
                text(kind == .transfer ? "" : t.category?.name ?? ""), text(t.wallet?.name ?? ""), text(kind == .transfer ? t.toWallet?.name ?? "" : ""),
                text(t.note), t.recurrenceKey == nil ? "" : "Có", t.id.uuidString])
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data((rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
    static func write(_ data: Data, range: DateInterval, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = formatter("yyyy-MM-dd"), last = range.end.addingTimeInterval(-1)
        let url = directory.appendingPathComponent("SaveMoney_\(date.string(from: range.start))_\(date.string(from: last)).csv")
        try data.write(to: url, options: .atomic); return url
    }
    static func cleanTemporaryFiles() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private static func text(_ value: String) -> String {
        guard let first = value.first, ["=", "+", "-", "@", "\t", "\r", "\n"].contains(first) else { return value }
        return "'" + value
    }
    private static func quote(_ value: String) -> String {
        value.contains(where: { [",", "\"", "\r", "\n"].contains($0) }) ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter(); formatter.calendar = LocalCalendar.calendar; formatter.timeZone = LocalCalendar.calendar.timeZone
        formatter.locale = Locale(identifier: "vi_VN"); formatter.dateFormat = pattern; return formatter
    }
}
