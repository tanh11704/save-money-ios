import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var icon: String = "tag"
    var isArchived: Bool = false
    /// Paid in lump sums (rent, bills, tuition) rather than day by day. Fixed expenses are taken out of the
    /// budget up front instead of being spread over the days of the cycle. Only meaningful for expenses.
    var isFixed: Bool = false

    init(name: String, kind: TransactionKind, icon: String = "tag") {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon
    }
}
