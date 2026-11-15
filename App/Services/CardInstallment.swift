import Foundation

// MARK: - Credit cards

/// Extra settings for a wallet of kind `.card`. Kept in UserDefaults per wallet so the
/// SwiftData schema and the backup format stay unchanged; losing them loses no money data.
struct CreditCardSettings: Codable, Equatable {
    /// Credit limit in đồng; nil when unknown.
    var limit: Int64?
    /// Day of month the statement closes (1–31, clamped to short months).
    var statementDay: Int = 25
    /// Day of month payment is due (1–31, clamped). Falls in the month after the statement when ≤ statementDay.
    var dueDay: Int = 10
    var remindsBeforeDue = true

    var isValid: Bool {
        (1...31).contains(statementDay) && (1...31).contains(dueDay) && (limit.map { (1...MoneyFormatter.maximumInput).contains($0) } ?? true)
    }
}

enum CreditCardSettingsStore {
    static func key(_ walletID: UUID) -> String { "SaveMoney.card.\(walletID.uuidString)" }

    static func load(_ walletID: UUID, defaults: UserDefaults = .standard) -> CreditCardSettings? {
        guard let data = defaults.data(forKey: key(walletID)),
              let settings = try? JSONDecoder().decode(CreditCardSettings.self, from: data), settings.isValid else { return nil }
        return settings
    }

    static func save(_ settings: CreditCardSettings?, for walletID: UUID, defaults: UserDefaults = .standard) {
        guard let settings, settings.isValid, let data = try? JSONEncoder().encode(settings) else {
            defaults.removeObject(forKey: key(walletID)); return
        }
        defaults.set(data, forKey: key(walletID))
    }
}

struct CreditCardStatus: Equatable {
    /// What is owed on the card now (0 when the balance is positive).
    let debt: Int64
    /// `limit − debt`; nil without a limit. Negative when over the limit.
    let available: Int64?
    /// Display-only debt/limit.
    var usedFraction: Double? { limitValue.map { $0 > 0 ? min(1, Double(debt) / Double($0)) : 0 } }
    let limitValue: Int64?
    /// First day of the open statement period.
    let periodStart: Date
    /// Day the open statement closes (inclusive).
    let statementDate: Date
    /// Money that left the card (spending and transfers out) in the open period.
    let spentThisPeriod: Int64
    /// Next payment deadline: of the last closed statement if not yet passed, else of the open one.
    let dueDate: Date
    let daysUntilDue: Int

    /// The day `day` (clamped) in the month `offset` months after the month of `date`.
    static func date(day: Int, monthOffset offset: Int, from date: Date) -> Date {
        let calendar = LocalCalendar.calendar
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let month = calendar.date(byAdding: .month, value: offset, to: first)!
        let days = calendar.range(of: .day, in: .month, for: month)!.count
        return calendar.date(byAdding: .day, value: min(day, days) - 1, to: month)!
    }

    /// The due date that belongs to the statement closing on `statement`.
    static func dueDate(forStatement statement: Date, settings: CreditCardSettings) -> Date {
        let sameMonth = date(day: settings.dueDay, monthOffset: 0, from: statement)
        return sameMonth > statement ? sameMonth : date(day: settings.dueDay, monthOffset: 1, from: statement)
    }

    static func make(wallet: Wallet, balance: Int64, settings: CreditCardSettings,
                     transactions: [Transaction], now: Date = Date()) -> CreditCardStatus {
        let calendar = LocalCalendar.calendar
        let today = calendar.startOfDay(for: now)
        // The open period ends on the first statement day on or after today.
        let thisMonth = date(day: settings.statementDay, monthOffset: 0, from: today)
        let statement = thisMonth >= today ? thisMonth : date(day: settings.statementDay, monthOffset: 1, from: today)
        let lastStatement = date(day: settings.statementDay, monthOffset: -1, from: statement)
        let periodStart = calendar.date(byAdding: .day, value: 1, to: lastStatement)!
        let periodEnd = calendar.date(byAdding: .day, value: 1, to: statement)!
        var spent: Int64 = 0
        for transaction in transactions where transaction.wallet?.id == wallet.id
            && transaction.date >= periodStart && transaction.date < periodEnd
            && transaction.kindRaw != TransactionKind.income.rawValue {
            let sum = spent.addingReportingOverflow(transaction.amount)
            spent = sum.overflow ? .max : sum.partialValue
        }
        let previousDue = dueDate(forStatement: lastStatement, settings: settings)
        let due = previousDue >= today ? previousDue : dueDate(forStatement: statement, settings: settings)
        let debt = balance < 0 ? Int64(clamping: balance.magnitude) : 0
        return CreditCardStatus(debt: debt, available: settings.limit.map { $0 - debt }, limitValue: settings.limit,
                                periodStart: periodStart, statementDate: statement, spentThisPeriod: spent, dueDate: due,
                                daysUntilDue: calendar.dateComponents([.day], from: today, to: due).day!)
    }
}

// MARK: - Installments

/// An installment plan is a recurring rule with an end date: "12 kỳ × 2.000.000 ₫, ngày 10".
/// Reusing RecurringRule keeps generation, backup and restore exactly as they are.
struct InstallmentProgress: Equatable {
    let ruleID: UUID
    let title: String
    let perPeriod: Int64
    let totalPeriods: Int
    let paidPeriods: Int
    let nextDate: Date?
    let endDate: Date
    let isPaused: Bool
    var remainingPeriods: Int { max(0, totalPeriods - paidPeriods) }
    var total: Int64 { perPeriod.multipliedReportingOverflow(by: Int64(totalPeriods)).partialValue }
    var paid: Int64 { perPeriod.multipliedReportingOverflow(by: Int64(paidPeriods)).partialValue }
    var remaining: Int64 { perPeriod.multipliedReportingOverflow(by: Int64(remainingPeriods)).partialValue }
    var isFinished: Bool { remainingPeriods == 0 }
    /// Display only.
    var fraction: Double { totalPeriods > 0 ? Double(paidPeriods) / Double(totalPeriods) : 0 }

    static let maximumPeriods = 360

    /// Nil for open-ended rules or rules that cannot be read.
    static func make(_ rule: RecurringRule) -> InstallmentProgress? {
        guard let end = rule.endDate, let draft = rule.draft else { return nil }
        let all = RecurrenceCalculator.occurrences(start: draft.startDate, frequency: draft.frequency, interval: draft.interval,
                                                   end: end, after: nil, through: end, limit: maximumPeriods + 1)
        guard !all.isEmpty, all.count <= maximumPeriods else { return nil }
        let paid = rule.generatedThrough.map { through in all.filter { $0 <= through }.count } ?? 0
        return InstallmentProgress(ruleID: rule.id, title: rule.title, perPeriod: rule.amount, totalPeriods: all.count,
                                   paidPeriods: paid, nextDate: RecurringPresentation.nextDate(rule), endDate: all.last!, isPaused: rule.isPaused)
    }

    /// End date for `periods` payments starting on `start` (the last payment day).
    static func endDate(start: Date, periods: Int, frequency: RecurrenceFrequency = .monthly, interval: Int = 1) -> Date? {
        guard (1...maximumPeriods).contains(periods), interval >= 1 else { return nil }
        let calendar = LocalCalendar.calendar
        let component: Calendar.Component
        var step = interval
        switch frequency {
        case .daily: component = .day
        case .weekly: component = .day; step = interval * 7
        case .monthly: component = .month
        case .yearly: component = .year
        }
        return calendar.date(byAdding: component, value: (periods - 1) * step, to: calendar.startOfDay(for: start))
    }
}
