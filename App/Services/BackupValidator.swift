import Foundation

struct BackupValidator {
    struct Graph {
        let wallets: [Wallet]
        let categories: [Category]
        let transactions: [Transaction]
        var budgets: [Budget] = []
        var recurringRules: [RecurringRule] = []
    }
    struct Validated {
        let file: BackupFile
        let totalBalance: Int64
        let firstDate: Date?
        let lastDate: Date?
    }

    static func decode(_ data: Data, protection: BackupProtection = BackupProtection(), password: String? = nil) throws -> Validated {
        try read(protection.plaintext(data, password: password))
    }

    static func read(_ data: Data) throws -> Validated {
        struct Header: Decodable { let format: String; let schemaVersion: Int }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw BackupError.unreadable }
        guard header.format == "savemoney-backup" else { throw BackupError.wrongFormat }
        guard (1...3).contains(header.schemaVersion) else { throw BackupError.unsupportedVersion(header.schemaVersion) }
        let file: BackupFile
        do { file = try JSONDecoder().decode(BackupFile.self, from: data) }
        catch { throw BackupError.unreadable }
        return try validate(file)
    }

    static func validate(_ file: BackupFile) throws -> Validated {
        guard file.format == "savemoney-backup" else { throw BackupError.wrongFormat }
        guard (1...3).contains(file.schemaVersion) else { throw BackupError.unsupportedVersion(file.schemaVersion) }
        guard try BackupFile.digest(file.payload) == file.checksum else { throw BackupError.checksum }
        _ = try BackupFile.date(file.createdAt)
        let p = file.payload
        guard file.summary.wallets == p.wallets.count, file.summary.categories == p.categories.count,
              file.summary.transactions == p.transactions.count else { throw BackupError.structure("Số lượng không khớp tóm tắt.") }
        if file.schemaVersion >= 2 {
            guard p.includesBudgets, file.summary.budgets == p.budgets.count else {
                throw BackupError.structure("Thiếu hạn mức hoặc số lượng hạn mức không khớp.")
            }
        } else if p.includesBudgets || !p.budgets.isEmpty {
            throw BackupError.structure("Bản sao lưu v1 không chứa hạn mức.")
        }
        if file.schemaVersion == 3 {
            guard p.includesRecurringRules, file.summary.recurringRules == p.recurringRules.count,
                  p.transactions.allSatisfy({ $0.includesRecurrenceKey }) else {
                throw BackupError.structure("Thiếu quy tắc định kỳ hoặc khóa giao dịch trong bản v3.")
            }
        } else if p.includesRecurringRules || !p.recurringRules.isEmpty || p.transactions.contains(where: { $0.includesRecurrenceKey || $0.recurrenceKey != nil }) {
            throw BackupError.structure("Bản sao lưu cũ không chứa dữ liệu định kỳ.")
        }
        let graph = try graph(p)
        let balances = try expectedBalances(graph)
        guard balances == file.summary.expectedBalances else { throw BackupError.balances }
        let dates = graph.transactions.map(\.date)
        return Validated(file: file, totalBalance: try BalanceCalculator.totalBalance(wallets: graph.wallets, transactions: graph.transactions),
                         firstDate: dates.min(), lastDate: dates.max())
    }

    static func graph(_ payload: BackupFile.Payload) throws -> Graph {
        var seen = Set<String>()
        func id(_ text: String) throws -> UUID {
            guard let id = UUID(uuidString: text), id.uuidString == text, seen.insert(text).inserted else {
                throw BackupError.structure("ID không hợp lệ hoặc bị trùng.")
            }
            return id
        }
        var wallets: [String: Wallet] = [:]
        var categories: [String: Category] = [:]
        var transactions: [Transaction] = []
        for record in payload.wallets {
            let uuid = try id(record.id)
            guard let kind = WalletKind(rawValue: record.kind) else { throw BackupError.structure("Loại ví không hợp lệ.") }
            let wallet = Wallet(name: record.name, openingBalance: record.openingBalance, kind: kind)
            wallet.id = uuid; wallet.isArchived = record.isArchived; wallet.createdAt = try BackupFile.date(record.createdAt)
            wallets[record.id] = wallet
        }
        for record in payload.categories {
            let uuid = try id(record.id)
            guard let kind = TransactionKind(rawValue: record.kind), kind != .transfer else { throw BackupError.structure("Loại danh mục không hợp lệ.") }
            let category = Category(name: record.name, kind: kind, icon: record.icon)
            category.id = uuid; category.isArchived = record.isArchived; categories[record.id] = category
        }
        var recurrenceKeys = Set<String>()
        for record in payload.transactions {
            let uuid = try id(record.id)
            guard record.amount > 0, let kind = TransactionKind(rawValue: record.kind),
                  let sourceID = record.walletId, let wallet = wallets[sourceID] else {
                throw BackupError.structure("Giao dịch thiếu ví, sai loại hoặc số tiền không dương.")
            }
            let destination = record.toWalletId.flatMap { wallets[$0] }
            let category = record.categoryId.flatMap { categories[$0] }
            guard record.toWalletId == nil || destination != nil, record.categoryId == nil || category != nil else {
                throw BackupError.structure("Tham chiếu đến ví hoặc danh mục không tồn tại.")
            }
            if kind == .transfer {
                guard let destination, destination.id != wallet.id, category == nil else {
                    throw BackupError.structure("Chuyển tiền cần hai ví khác nhau và không có danh mục.")
                }
            } else {
                guard destination == nil, let category, category.kindRaw == record.kind else {
                    throw BackupError.structure("Khoản thu/chi cần danh mục đúng loại và không có ví nhận.")
                }
            }
            let transaction = Transaction(amount: record.amount, kind: kind, date: try BackupFile.date(record.date),
                note: record.note, wallet: wallet, toWallet: destination, category: category)
            if let key = record.recurrenceKey {
                let parts = key.split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count == 2, let ruleID = UUID(uuidString: String(parts[0])), ruleID.uuidString == parts[0],
                      parts[1].count == 8, parts[1].utf8.allSatisfy({ (48...57).contains($0) }), recurrenceKeys.insert(key).inserted else {
                    throw BackupError.structure("Khóa định kỳ không hợp lệ hoặc bị trùng.")
                }
            }
            transaction.id = uuid; transaction.recurrenceKey = record.recurrenceKey; transactions.append(transaction)
        }
        var budgets: [Budget] = []
        var scopes = Set<String>()
        for record in payload.budgets {
            let uuid = try id(record.id)
            guard (1...MoneyFormatter.maximumInput).contains(record.limit),
                  (try? ReportingMonth(year: record.startYear, month: record.startMonth)) != nil else {
                throw BackupError.structure("Số tiền hoặc tháng của hạn mức không hợp lệ.")
            }
            let category = record.categoryID.flatMap { categories[$0] }
            switch record.scopeRaw {
            case "total":
                guard record.categoryID == nil else { throw BackupError.structure("Hạn mức tổng không có danh mục.") }
            case "category":
                guard let category, category.kindRaw == TransactionKind.expense.rawValue else {
                    throw BackupError.structure("Hạn mức phải trỏ tới danh mục chi tồn tại.")
                }
            default: throw BackupError.structure("Phạm vi hạn mức không hợp lệ.")
            }
            let key = "\(record.scopeRaw).\(record.categoryID ?? "").\(record.startYear).\(record.startMonth)"
            guard scopes.insert(key).inserted else { throw BackupError.structure("Hạn mức trùng phạm vi và tháng bắt đầu.") }
            let budget = Budget(); budget.id = uuid; budget.scopeRaw = record.scopeRaw; budget.category = category
            budget.limit = record.limit; budget.startYear = record.startYear; budget.startMonth = record.startMonth
            budget.isArchived = record.isArchived; budget.createdAt = try BackupFile.date(record.createdAt)
            budgets.append(budget)
        }
        var recurringRules: [RecurringRule] = []
        for record in payload.recurringRules {
            let uuid = try id(record.id)
            guard let kind = TransactionKind(rawValue: record.kindRaw),
                  RecurrenceFrequency(rawValue: record.frequencyRaw) != nil,
                  (1...MoneyFormatter.maximumInput).contains(record.amount), record.interval >= 1,
                  let sourceID = record.walletId, let wallet = wallets[sourceID] else {
                throw BackupError.structure("Quy tắc định kỳ sai loại, chu kỳ, số tiền hoặc thiếu ví.")
            }
            let destination = record.toWalletId.flatMap { wallets[$0] }, category = record.categoryId.flatMap { categories[$0] }
            guard record.toWalletId == nil || destination != nil, record.categoryId == nil || category != nil else { throw BackupError.structure("Quy tắc định kỳ có tham chiếu bị thiếu.") }
            if kind == .transfer {
                guard let destination, destination.id != wallet.id, category == nil else { throw BackupError.structure("Chuyển tiền định kỳ cần hai ví khác nhau và không có danh mục.") }
            } else {
                guard destination == nil, let category, category.kindRaw == kind.rawValue else { throw BackupError.structure("Danh mục định kỳ không đúng loại.") }
            }
            let start = try BackupFile.date(record.startDate), end = try record.endDate.map(BackupFile.date)
            guard end.map({ $0 >= start }) ?? true else { throw BackupError.structure("Ngày kết thúc định kỳ trước ngày bắt đầu.") }
            let rule = RecurringRule(); rule.id = uuid; rule.name = record.name; rule.kindRaw = record.kindRaw; rule.amount = record.amount; rule.note = record.note
            rule.wallet = wallet; rule.toWallet = destination; rule.category = category
            rule.frequencyRaw = record.frequencyRaw; rule.interval = record.interval; rule.startDate = start; rule.endDate = end
            rule.generatedThrough = try record.generatedThrough.map(BackupFile.date); rule.isPaused = record.isPaused; rule.createdAt = try BackupFile.date(record.createdAt)
            recurringRules.append(rule)
        }
        return Graph(wallets: Array(wallets.values), categories: Array(categories.values), transactions: transactions, budgets: budgets, recurringRules: recurringRules)
    }

    static func expectedBalances(_ graph: Graph) throws -> [String: Int64] {
        var balances: [String: Int64] = [:]
        for wallet in graph.wallets {
            balances[wallet.id.uuidString] = try BalanceCalculator.balance(for: wallet, transactions: graph.transactions)
        }
        return balances
    }
}
