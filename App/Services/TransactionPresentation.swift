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

    /// A balance adjustment: a transfer between an own wallet and the hidden adjustment wallet.
    static func isAdjustment(_ transaction: Transaction) -> Bool {
        transaction.kindRaw == TransactionKind.transfer.rawValue
            && (transaction.wallet?.isAdjustment == true || transaction.toWallet?.isAdjustment == true)
    }

    /// The adjusted own wallet and whether its balance went up.
    static func adjustment(_ transaction: Transaction) -> (wallet: Wallet?, increased: Bool)? {
        guard isAdjustment(transaction) else { return nil }
        let increased = transaction.wallet?.isAdjustment == true
        return (increased ? transaction.toWallet : transaction.wallet, increased)
    }

    static func amount(_ transaction: Transaction) -> String {
        if let adjustment = adjustment(transaction) {
            return (adjustment.increased ? "+" : "−") + MoneyFormatter.string(from: transaction.amount)
        }
        let prefix: String
        switch TransactionKind(rawValue: transaction.kindRaw) {
        case .income: prefix = "+"
        case .expense: prefix = "−"
        default: prefix = ""
        }
        return prefix + MoneyFormatter.string(from: transaction.amount)
    }

    static func title(_ transaction: Transaction) -> String {
        if isAdjustment(transaction) { return WalletKind.adjustment.title }
        if transaction.kindRaw == TransactionKind.transfer.rawValue {
            return "Chuyển: \(transaction.wallet?.name ?? "Ví không xác định") → \(transaction.toWallet?.name ?? "Ví không xác định")"
        }
        return transaction.category?.name ?? "Không có danh mục"
    }

    static func accessibilityLabel(_ transaction: Transaction) -> String {
        if let adjustment = adjustment(transaction) {
            return "Điều chỉnh số dư \(adjustment.wallet?.name ?? ""), \(adjustment.increased ? "tăng" : "giảm") \(MoneyFormatter.string(from: transaction.amount))"
        }
        let kind = TransactionKind(rawValue: transaction.kindRaw).map(kindTitle) ?? "Giao dịch"
        return "\(kind), \(title(transaction)), \(MoneyFormatter.string(from: transaction.amount))" + (transaction.recurrenceKey == nil ? "" : ", Định kỳ")
    }

    static func errorMessage(_ error: Error) -> String {
        if let error = error as? ReportingMonth.MonthError { return error.localizedDescription }
        if let error = error as? ManagementError { return error.localizedDescription }
        if let error = error as? TransactionValidator.ValidationError { return error.localizedDescription }
        if let error = error as? TransactionService.ServiceError { return error.localizedDescription }
        if let error = error as? BalanceAdjustmentService.AdjustmentError { return error.localizedDescription }
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

    static func selectedDay(_ date: Date, now: Date = Date()) -> Date {
        let calendar = LocalCalendar.calendar
        if calendar.isDate(date, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    static func yesterday(from date: Date = Date()) -> Date {
        selectedDay(LocalCalendar.calendar.date(byAdding: .day, value: -1, to: date)!, now: date)
    }
}
