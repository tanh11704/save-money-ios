import Foundation
import SwiftData

struct IntegrityIssue: Equatable, Identifiable {
    enum Severity: String, Codable { case error, warning }
    enum Kind: Equatable {
        case transactionMissingWallet(UUID), transactionMissingCategory(UUID), transferMissingDestination(UUID)
        case transferSameWallet(UUID), transferHasCategory(UUID), categoryKindMismatch(UUID), nonPositiveAmount(UUID)
        case duplicateID(String), duplicateRecurrenceKey(String), invalidBudget(UUID), invalidRecurringRule(UUID)
        case invalidTransaction(UUID), invalidWallet(UUID), balanceOverflow, balanceMismatch
        case backupUnreadable(String), backupChecksumMismatch(String), encryptedBackupUnchecked(String)
    }
    let id = UUID()
    let kind: Kind
    let severity: Severity
    var message: String {
        let detail: String
        switch kind {
        case .transactionMissingWallet(let id): detail = "Giao dịch \(id) thiếu ví hợp lệ."
        case .transactionMissingCategory(let id): detail = "Giao dịch cũ \(id) thiếu danh mục."
        case .transferMissingDestination(let id): detail = "Chuyển tiền \(id) thiếu ví nhận."
        case .transferSameWallet(let id): detail = "Chuyển tiền \(id) có hai ví trùng nhau."
        case .transferHasCategory(let id): detail = "Chuyển tiền \(id) có danh mục."
        case .categoryKindMismatch(let id): detail = "Giao dịch \(id) dùng danh mục sai loại."
        case .nonPositiveAmount(let id): detail = "Giao dịch \(id) có số tiền không dương."
        case .duplicateID(let id): detail = "ID trùng: \(id)."
        case .duplicateRecurrenceKey(let key): detail = "Khóa định kỳ trùng: \(key)."
        case .invalidBudget(let id): detail = "Hạn mức \(id) không hợp lệ."
        case .invalidRecurringRule(let id): detail = "Quy tắc định kỳ \(id) cần xem lại ví, danh mục, chu kỳ hoặc ngày."
        case .invalidWallet(let id): detail = "Ví \(id) có loại hoặc số dư ban đầu không hợp lệ."
        case .invalidTransaction(let id): detail = "Giao dịch \(id) không hợp lệ."
        case .balanceOverflow: detail = "Không tính được số dư trong phạm vi Int64."
        case .balanceMismatch: detail = "Tổng số dư các ví không khớp tổng số dư ban đầu cộng thu trừ chi."
        case .backupUnreadable(let name): return "Không đọc được bản \(name). Giữ file để kiểm tra và tạo bản sao lưu mới."
        case .backupChecksumMismatch(let name): return "Checksum bản \(name) không khớp. Không khôi phục file này; chọn bản khác hoặc tạo bản mới."
        case .encryptedBackupUnchecked(let name): return "Chưa kiểm tra \(name) (đã mã hóa). Nhập mật khẩu để kiểm tra file."
        }
        return detail + " Hãy sửa qua màn hình tương ứng hoặc khôi phục một bản sao lưu đã kiểm tra. Không tự động sửa dữ liệu."
    }
}

struct IntegrityReport {
    let checkedAt: Date
    let issues: [IntegrityIssue]
    let transactionCount: Int
    let totalBalance: Int64?
    let backupFilesChecked: Int
    var isHealthy: Bool { !issues.contains { $0.severity == .error } }
}

struct IntegrityChecker {
    @MainActor
    static func check(container: ModelContainer, backupDirectory: URL?) throws -> IntegrityReport {
        let context = ModelContext(container); context.autosaveEnabled = false
        let report = try inspect(wallets: context.fetch(FetchDescriptor<Wallet>()), categories: context.fetch(FetchDescriptor<Category>()),
            transactions: context.fetch(FetchDescriptor<Transaction>()), budgets: context.fetch(FetchDescriptor<Budget>()), recurring: context.fetch(FetchDescriptor<RecurringRule>()))
        let files = try backupDirectory.map { try checkFiles(in: $0) } ?? (issues: [], checked: 0)
        return IntegrityReport(checkedAt: report.checkedAt, issues: report.issues + files.issues, transactionCount: report.transactionCount,
            totalBalance: report.totalBalance, backupFilesChecked: files.checked)
    }

    static func inspect(wallets: [Wallet], categories: [Category], transactions: [Transaction], budgets: [Budget], recurring: [RecurringRule]) throws -> IntegrityReport {
        var issues: [IntegrityIssue] = []
        func add(_ kind: IntegrityIssue.Kind, _ severity: IntegrityIssue.Severity = .error) { issues.append(IntegrityIssue(kind: kind, severity: severity)) }
        for ids in [wallets.map(\.id), categories.map(\.id), transactions.map(\.id), budgets.map(\.id), recurring.map(\.id)] {
            var seen = Set<UUID>()
            for id in ids where !seen.insert(id).inserted { add(.duplicateID(id.uuidString)) }
        }
        let walletIDs = Set(wallets.map(\.id)), categoryIDs = Set(categories.map(\.id))
        for wallet in wallets where WalletKind(rawValue: wallet.kindRaw) == nil || (wallet.isPerson && wallet.openingBalance != 0) { add(.invalidWallet(wallet.id)) }
        var keys = Set<String>()
        for t in transactions {
            if let wallet = t.wallet, !walletIDs.contains(wallet.id) { add(.transactionMissingWallet(t.id)) }
            if let destination = t.toWallet, !walletIDs.contains(destination.id) { add(.transferMissingDestination(t.id)) }
            if let category = t.category, !categoryIDs.contains(category.id) { add(.transactionMissingCategory(t.id), .warning) }
            if let kind = TransactionKind(rawValue: t.kindRaw) {
                let draft = TransactionDraft(amount: t.amount, kind: kind, date: t.date, note: t.note, wallet: t.wallet, toWallet: t.toWallet, category: t.category)
                for error in TransactionValidator.validationErrors(draft, editing: t) {
                    switch error {
                    case .invalidAmount: add(.nonPositiveAmount(t.id))
                    case .amountTooLarge: add(.invalidTransaction(t.id), .warning)
                    case .missingWallet: add(.transactionMissingWallet(t.id))
                    case .missingCategory: add(.transactionMissingCategory(t.id), .warning)
                    case .missingDestination: add(.transferMissingDestination(t.id))
                    case .sameWallet: add(.transferSameWallet(t.id))
                    case .unexpectedCategory: add(.transferHasCategory(t.id))
                    case .categoryKindMismatch: add(.categoryKindMismatch(t.id))
                    case .unexpectedDestination, .personToPerson, .incomeToPerson: add(.invalidTransaction(t.id))
                    case .archivedWallet, .archivedDestination, .archivedCategory: break
                    }
                }
            } else { add(.invalidTransaction(t.id)) }
            if let key = t.recurrenceKey, !keys.insert(key).inserted { add(.duplicateRecurrenceKey(key)) }
        }
        for budget in budgets where budget.rule == nil { add(.invalidBudget(budget.id)) }
        for rule in recurring {
            guard let draft = rule.draft else { add(.invalidRecurringRule(rule.id)); continue }
            do { try RecurringValidator.validate(draft) }
            catch {
                let archived = [draft.transaction.wallet?.isArchived, draft.transaction.toWallet?.isArchived, draft.transaction.category?.isArchived].contains(true)
                add(.invalidRecurringRule(rule.id), archived ? .warning : .error)
            }
        }
        var balance: Int64?
        do {
            balance = try BalanceCalculator.totalBalance(wallets: wallets, transactions: transactions, allowMissingCategory: true)
            let flow = try BalanceCalculator.flowTotals(transactions: transactions, allowMissingCategory: true)
            func checked(_ a: Int64, _ b: Int64) throws -> Int64 {
                let value = a.addingReportingOverflow(b)
                guard !value.overflow else { throw BalanceCalculator.CalculationError.overflow }
                return value.partialValue
            }
            let opening = try wallets.reduce(Int64(0)) { try checked($0, $1.openingBalance) }
            let independent = try checked(checked(opening, flow.income), -flow.expense)
            if independent != balance { add(.balanceMismatch) }
        } catch BalanceCalculator.CalculationError.overflow { add(.balanceOverflow); balance = nil }
        catch { balance = nil } // The individual structural issues above explain invalid transactions.
        return IntegrityReport(checkedAt: Date(), issues: issues, transactionCount: transactions.count, totalBalance: balance, backupFilesChecked: 0)
    }

    static func checkFiles(in directory: URL, protection: BackupProtection = BackupProtection()) throws -> (issues: [IntegrityIssue], checked: Int) {
        var issues: [IntegrityIssue] = [], checked = 0
        for url in try files(in: directory) {
            do { _ = try BackupValidator.decode(Data(contentsOf: url), protection: protection); checked += 1 }
            catch BackupCrypto.CryptoError.keyUnavailable { issues.append(.init(kind: .encryptedBackupUnchecked(url.lastPathComponent), severity: .warning)) }
            catch BackupError.checksum { issues.append(.init(kind: .backupChecksumMismatch(url.lastPathComponent), severity: .error)) }
            catch { issues.append(.init(kind: .backupUnreadable(url.lastPathComponent), severity: .error)) }
        }
        return (issues, checked)
    }
    static func files(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let nested = (try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("PreRestore"), includingPropertiesForKeys: nil)) ?? []
        return (files + nested).filter { ["json", "savemoney"].contains($0.pathExtension) }
    }
}
