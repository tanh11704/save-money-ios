import CryptoKit
import Foundation

struct BackupFile: Codable, Equatable {
    var format: String = "savemoney-backup"
    var schemaVersion: Int = 1
    var createdAt: Int64
    var appVersion: String
    var checksum: String
    var summary: Summary
    var payload: Payload

    struct Summary: Codable, Equatable {
        var wallets: Int
        var categories: Int
        var transactions: Int
        var budgets: Int? = nil
        var expectedBalances: [String: Int64]
    }
    struct Payload: Codable, Equatable {
        var wallets: [WalletRecord]
        var categories: [CategoryRecord]
        var transactions: [TransactionRecord]
        var budgets: [BudgetRecord] = []
        private(set) var includesBudgets: Bool = false
        var isEmpty: Bool { wallets.isEmpty && categories.isEmpty && transactions.isEmpty && budgets.isEmpty }
        enum CodingKeys: String, CodingKey { case wallets, categories, transactions, budgets }
        init(wallets: [WalletRecord], categories: [CategoryRecord], transactions: [TransactionRecord], budgets: [BudgetRecord]? = nil) {
            self.wallets = wallets; self.categories = categories; self.transactions = transactions
            self.budgets = budgets ?? []; includesBudgets = budgets != nil
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wallets = try c.decode([WalletRecord].self, forKey: .wallets)
            categories = try c.decode([CategoryRecord].self, forKey: .categories)
            transactions = try c.decode([TransactionRecord].self, forKey: .transactions)
            includesBudgets = c.contains(.budgets)
            budgets = includesBudgets ? try c.decode([BudgetRecord].self, forKey: .budgets) : []
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(wallets, forKey: .wallets); try c.encode(categories, forKey: .categories)
            try c.encode(transactions, forKey: .transactions)
            if includesBudgets || !budgets.isEmpty { try c.encode(budgets, forKey: .budgets) }
        }
    }
    struct BudgetRecord: Codable, Equatable {
        var id: String
        var scopeRaw: String
        var categoryID: String?
        var limit: Int64
        var startYear: Int
        var startMonth: Int
        var isArchived: Bool
        var createdAt: Int64
        enum CodingKeys: String, CodingKey { case id, scopeRaw, categoryID, limit, startYear, startMonth, isArchived, createdAt }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(scopeRaw, forKey: .scopeRaw)
            try c.encode(categoryID, forKey: .categoryID); try c.encode(limit, forKey: .limit)
            try c.encode(startYear, forKey: .startYear); try c.encode(startMonth, forKey: .startMonth)
            try c.encode(isArchived, forKey: .isArchived); try c.encode(createdAt, forKey: .createdAt)
        }
    }
    struct WalletRecord: Codable, Equatable {
        var id: String
        var name: String
        var kind: String
        var openingBalance: Int64
        var isArchived: Bool
        var createdAt: Int64
    }
    struct CategoryRecord: Codable, Equatable {
        var id: String
        var name: String
        var kind: String
        var icon: String
        var isArchived: Bool
    }
    struct TransactionRecord: Codable, Equatable {
        var id: String
        var amount: Int64
        var kind: String
        var date: Int64
        var note: String
        var walletId: String?
        var toWalletId: String?
        var categoryId: String?
        enum CodingKeys: String, CodingKey { case id, amount, kind, date, note, walletId, toWalletId, categoryId }
        init(id: String, amount: Int64, kind: String, date: Int64, note: String, walletId: String?, toWalletId: String?, categoryId: String?) {
            self.id = id; self.amount = amount; self.kind = kind; self.date = date; self.note = note
            self.walletId = walletId; self.toWalletId = toWalletId; self.categoryId = categoryId
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            amount = try c.decode(Int64.self, forKey: .amount)
            kind = try c.decode(String.self, forKey: .kind)
            date = try c.decode(Int64.self, forKey: .date)
            note = try c.decode(String.self, forKey: .note)
            walletId = try c.decode(String?.self, forKey: .walletId)
            toWalletId = try c.decode(String?.self, forKey: .toWalletId)
            categoryId = try c.decode(String?.self, forKey: .categoryId)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(amount, forKey: .amount)
            try c.encode(kind, forKey: .kind); try c.encode(date, forKey: .date); try c.encode(note, forKey: .note)
            try c.encode(walletId, forKey: .walletId); try c.encode(toWalletId, forKey: .toWalletId); try c.encode(categoryId, forKey: .categoryId)
        }
    }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    static func digest(_ payload: Payload) throws -> String {
        SHA256.hash(data: try encoder().encode(payload)).map { String(format: "%02x", $0) }.joined()
    }
    static func milliseconds(_ date: Date) throws -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1_000 // Time only, never money.
        guard milliseconds.isFinite, milliseconds >= -62_135_596_800_000, milliseconds <= 253_402_300_799_999 else {
            throw BackupError.structure("Thời gian nằm ngoài phạm vi được hỗ trợ.")
        }
        return Int64(milliseconds.rounded())
    }
    static func date(_ milliseconds: Int64) throws -> Date {
        guard (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else {
            throw BackupError.structure("Thời gian nằm ngoài phạm vi được hỗ trợ.")
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}

enum BackupError: LocalizedError, Equatable {
    case unreadable, wrongFormat, unsupportedVersion(Int), checksum, structure(String), balances, preRestore, collision
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Không đọc được bản sao lưu. File không phải JSON SaveMoney, bị hỏng hoặc thiếu trường."
        case .wrongFormat: return "File không phải bản sao lưu SaveMoney."
        case .unsupportedVersion(let version): return "Định dạng sao lưu phiên bản \(version) chưa được hỗ trợ."
        case .checksum: return "Checksum không khớp. File đã bị hỏng hoặc thay đổi."
        case .structure(let message): return "Dữ liệu sao lưu không hợp lệ: \(message)"
        case .balances: return "Số dư trong file không khớp dữ liệu giao dịch."
        case .preRestore: return "Không tạo được bản sao lưu trước khôi phục. Dữ liệu hiện tại được giữ nguyên."
        case .collision: return "Không tìm được tên file sao lưu mới. Các bản cũ được giữ nguyên."
        }
    }
}
