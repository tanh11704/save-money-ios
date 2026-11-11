import Foundation
import SwiftData

enum WalletKind: String, Codable, CaseIterable {
    case cash, bank, card, other, person
    /// Hidden system wallet: the counterpart of balance adjustments. Never shown as a wallet.
    case adjustment

    var title: String {
        switch self {
        case .cash: return "Tiền mặt"
        case .bank: return "Ngân hàng"
        case .card: return "Thẻ"
        case .person: return "Người"
        case .adjustment: return "Điều chỉnh số dư"
        case .other: return "Khác"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .card: return "creditcard"
        case .person: return "person.crop.circle"
        case .adjustment: return "slider.horizontal.3"
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

extension Wallet {
    var isPerson: Bool { WalletKind(rawValue: kindRaw) == .person }
    var isAdjustment: Bool { WalletKind(rawValue: kindRaw) == .adjustment }
    /// A wallet the user actually holds money in: not a debt counterpart and not the adjustment wallet.
    var isOwn: Bool { !isPerson && !isAdjustment }
}
