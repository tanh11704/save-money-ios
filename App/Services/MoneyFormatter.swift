import Foundation

struct MoneyFormatter {
    static let maximumInput: Int64 = 999_999_999_999

    enum Key: Equatable {
        case plus, minus, equals, clear
        case digit(Int)
        case tripleZero
        case backspace
    }

    /// Also supports signed balances, including Int64.min, without negation overflow.
    static func string(from amount: Int64) -> String {
        let digits = String(amount.magnitude)
        var groups: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.append(String(digits[start..<end]))
            end = start
        }
        return (amount < 0 ? "−" : "") + groups.reversed().joined(separator: ".") + " ₫"
    }

    /// Strict inverse for nonnegative input amounts, not a permissive money parser.
    /// Keyboard state itself always stays Int64; this is for explicit text conversion.
    static func amount(from text: String) -> Int64? {
        var text = text
        if text.hasSuffix(" ₫") { text.removeLast(2) }
        guard !text.isEmpty else { return nil }
        let groups = text.split(separator: ".", omittingEmptySubsequences: false)
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups[0].first != "0",
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int64(digits), value <= maximumInput else { return nil }
        return value
    }

    static func applying(_ key: Key, to amount: Int64) -> Int64 {
        guard amount >= 0 else { return amount }
        // An older record may exceed the new input cap; allow reducing it.
        if case .backspace = key { return amount / 10 }
        guard amount <= maximumInput else { return amount }
        let multiplier: Int64
        let suffix: Int64
        switch key {
        case .plus, .minus, .equals, .clear: return amount
        case .backspace: return amount / 10
        case .tripleZero: multiplier = 1_000; suffix = 0
        case .digit(let digit):
            guard (0...9).contains(digit) else { return amount }
            multiplier = 10; suffix = Int64(digit)
        }
        guard amount <= (maximumInput - suffix) / multiplier else { return amount }
        return amount * multiplier + suffix
    }
}
