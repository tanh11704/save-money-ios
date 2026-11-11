import Foundation

/// Stable across launches and platforms; never uses Swift's randomized hashValue.
enum CategoryPalette {
    static func index(for icon: String) -> Int {
        switch icon {
        case "fork.knife", "cup.and.saucer": return 1
        case "bus", "car", "bicycle", "airplane", "tram": return 2
        case "bag", "cart", "gift": return 3
        case "house": return 4
        case "heart", "cross.case": return 5
        case "banknote", "plus.circle": return 6
        case "book", "graduationcap": return 7
        case "gamecontroller", "film", "music.note": return 8
        case "bolt", "fuelpump": return 9
        case "drop", "wifi", "phone": return 10
        default:
            let hash = icon.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            return Int(hash % 10) + 1
        }
    }
}
