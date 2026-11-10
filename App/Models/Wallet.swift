import Foundation
import SwiftData

enum WalletKind: String, Codable, CaseIterable {
    case cash, bank, card, other

    var title: String {
        switch self {
        case .cash: return "Tiền mặt"
        case .bank: return "Ngân hàng"
        case .card: return "Thẻ"
        case .other: return "Khác"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .card: return "creditcard"
        case .other: return "wallet.bifold"
        }
    }
}

@Model
final class Wallet {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = "cash"
    var openingBalance: Int64 = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(name: String, openingBalance: Int64 = 0, kind: WalletKind = .cash) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.openingBalance = openingBalance
    }
}
