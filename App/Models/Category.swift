import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var icon: String = "tag"
    var isArchived: Bool = false

    init(name: String, kind: TransactionKind, icon: String = "tag") {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon
    }
}
