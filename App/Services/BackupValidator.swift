import Foundation

struct BackupValidator {
    struct Graph {
        let wallets: [Wallet]
        let categories: [Category]
        let transactions: [Transaction]
    }
    struct Validated {
        let file: BackupFile
        let totalBalance: Int64
        let firstDate: Date?
        let lastDate: Date?
    }

    static func read(_ data: Data) throws -> Validated {
        struct Header: Decodable { let format: String; let schemaVersion: Int }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw BackupError.unreadable }
        guard header.format == "savemoney-backup" else { throw BackupError.wrongFormat }
        guard header.schemaVersion == 1 else { throw BackupError.unsupportedVersion(header.schemaVersion) }
        let file: BackupFile
        do { file = try JSONDecoder().decode(BackupFile.self, from: data) }
        catch { throw BackupError.unreadable }
        return try validate(file)
    }

    static func validate(_ file: BackupFile) throws -> Validated {
        guard file.format == "savemoney-backup" else { throw BackupError.wrongFormat }
        guard file.schemaVersion == 1 else { throw BackupError.unsupportedVersion(file.schemaVersion) }
        guard try BackupFile.digest(file.payload) == file.checksum else { throw BackupError.checksum }
        _ = try BackupFile.date(file.createdAt)
        let p = file.payload
        guard file.summary.wallets == p.wallets.count, file.summary.categories == p.categories.count,
              file.summary.transactions == p.transactions.count else { throw BackupError.structure("Số lượng không khớp tóm tắt.") }
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
            transaction.id = uuid; transactions.append(transaction)
        }
        return Graph(wallets: Array(wallets.values), categories: Array(categories.values), transactions: transactions)
    }

    static func expectedBalances(_ graph: Graph) throws -> [String: Int64] {
        var balances: [String: Int64] = [:]
        for wallet in graph.wallets {
            balances[wallet.id.uuidString] = try BalanceCalculator.balance(for: wallet, transactions: graph.transactions)
        }
        return balances
    }
}
