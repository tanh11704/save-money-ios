import Foundation
import SwiftData

@Model
final class Wallet {
    var id: UUID = UUID()
    var name: String = ""
    var openingBalance: Int64 = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(name: String, openingBalance: Int64 = 0) {
        self.name = name
        self.openingBalance = openingBalance
    }
}
