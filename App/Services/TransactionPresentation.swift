import Foundation

struct TransactionPresentation {
    static func saveButtonTitle(for error: Error?) -> String {
        switch error as? TransactionValidator.ValidationError {
        case .invalidAmount: return "Nhập số tiền"
        case .missingCategory: return "Chọn danh mục"
        case .missingWallet: return "Chọn ví"
        case .missingDestination: return "Chọn ví nhận"
        default: return "Lưu"
        }
    }

    static func showsInlineError(_ error: TransactionValidator.ValidationError, amount: Int64) -> Bool {
        error != .missingCategory && !(error == .invalidAmount && amount == 0)
    }

    static func kindTitle(_ kind: TransactionKind) -> String {
        switch kind {
        case .expense: return "Chi"
        case .income: return "Thu"
        case .transfer: return "Chuyển"
        }
    }

    static func amount(_ transaction: Transaction) -> String {
        let prefix: String
        switch TransactionKind(rawValue: transaction.kindRaw) {
        case .income: prefix = "+"
        case .expense: prefix = "−"
        default: prefix = ""
        }
        return prefix + MoneyFormatter.string(from: transaction.amount)
    }

    static func title(_ transaction: Transaction) -> String {
        if transaction.kindRaw == TransactionKind.transfer.rawValue {
            return "Chuyển: \(transaction.wallet?.name ?? "Ví không xác định") → \(transaction.toWallet?.name ?? "Ví không xác định")"
        }
        return transaction.category?.name ?? "Không có danh mục"
    }

    static func accessibilityLabel(_ transaction: Transaction) -> String {
        let kind = TransactionKind(rawValue: transaction.kindRaw).map(kindTitle) ?? "Giao dịch"
        return "\(kind), \(title(transaction)), \(MoneyFormatter.string(from: transaction.amount))" + (transaction.recurrenceKey == nil ? "" : ", Định kỳ")
    }

    static func errorMessage(_ error: Error) -> String {
        if let error = error as? ReportingMonth.MonthError { return error.localizedDescription }
        if let error = error as? ManagementError { return error.localizedDescription }
        if let error = error as? TransactionValidator.ValidationError { return error.localizedDescription }
        if let error = error as? TransactionService.ServiceError { return error.localizedDescription }
        if error is BalanceCalculator.CalculationError {
            return "Không thể tính số dư. Dữ liệu không hợp lệ hoặc số tiền vượt giới hạn."
        }
        return "Không thể lưu hoặc đọc dữ liệu. Hãy thử lại. Dữ liệu đang nhập được giữ nguyên."
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.calendar = LocalCalendar.calendar
        formatter.timeZone = LocalCalendar.calendar.timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    static func yesterday(from date: Date = Date()) -> Date {
        LocalCalendar.calendar.date(byAdding: .day, value: -1, to: date)!
    }
}
