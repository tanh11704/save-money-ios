import Foundation

struct AmountExpression: Equatable {
    enum Operator: Equatable { case plus, minus }
    private(set) var terms: [(Operator, Int64)] = []
    private(set) var current: Int64?
    private(set) var pendingOperator: Operator?

    init(amount: Int64 = 0) { current = amount }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.pendingOperator == rhs.pendingOperator &&
        lhs.terms.elementsEqual(rhs.terms, by: { $0.0 == $1.0 && $0.1 == $1.1 })
    }

    var result: Int64? {
        var value: Int64 = 0
        var operands = terms
        if let current { operands.append((pendingOperator ?? .plus, current)) }
        for (operation, amount) in operands {
            let next = operation == .plus ? value.addingReportingOverflow(amount) : value.subtractingReportingOverflow(amount)
            guard !next.overflow else { return nil }
            value = next.partialValue
        }
        return value
    }

    var hasOperator: Bool { !terms.isEmpty || pendingOperator != nil }
    var displayText: String {
        var parts: [String] = []
        for (index, term) in terms.enumerated() {
            if index > 0 { parts.append(term.0 == .plus ? "+" : "−") }
            parts.append(Self.number(term.1))
        }
        if let pendingOperator { parts.append(pendingOperator == .plus ? "+" : "−") }
        if let current { parts.append(Self.number(current)) }
        return parts.joined(separator: " ")
    }

    private static func number(_ amount: Int64) -> String {
        String(MoneyFormatter.string(from: amount).dropLast(2))
    }

    mutating func apply(_ key: MoneyFormatter.Key) {
        let previous = self
        switch key {
        case .digit, .tripleZero:
            current = MoneyFormatter.applying(key, to: current ?? 0)
        case .plus, .minus:
            if terms.isEmpty && (current ?? 0) == 0 { return }
            if let current { terms.append((pendingOperator ?? .plus, current)) }
            current = nil
            pendingOperator = key == .plus ? .plus : .minus
        case .equals:
            guard let value = result, value >= 0 else { return }
            self = Self(amount: value)
        case .backspace:
            if let value = current, value != 0 {
                current = MoneyFormatter.applying(.backspace, to: value)
            } else if let last = terms.popLast() {
                current = last.1
                pendingOperator = terms.isEmpty ? nil : last.0
            } else { current = 0; pendingOperator = nil }
        case .clear: self = Self()
        }
        if result == nil { self = previous }
    }
}
