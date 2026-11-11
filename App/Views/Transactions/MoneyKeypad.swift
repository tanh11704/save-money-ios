import SwiftUI

struct MoneyKeypad: View {
    var showsOperators: Bool = false
    let press: (MoneyFormatter.Key) -> Void
    private var rows: [[String]] { showsOperators ? [["1", "2", "3", "delete"], ["4", "5", "6", "minus"], ["7", "8", "9", "plus"], ["000", "0", "clear", "equals"]] : [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "delete"]] }

    private let labels = ["plus": "+", "minus": "−", "equals": "=", "clear": "C"]
    private let voiceLabels = ["plus": "Cộng", "minus": "Trừ", "equals": "Bằng", "clear": "Xóa hết"]
    private func operatorKey(_ key: String) -> MoneyFormatter.Key? {
        switch key {
        case "plus": return .plus
        case "minus": return .minus
        case "equals": return .equals
        case "clear": return .clear
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            if let operation = operatorKey(key) { press(operation) }
                            else if key == "delete" { press(.backspace) }
                            else if key == "000" { press(.tripleZero) }
                            else if let digit = Int(key) { press(.digit(digit)) }
                        } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left") }
                                else { Text(labels[key] ?? key).monospacedDigit() }
                            }
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .tint(showsOperators ? (operatorKey(key) != nil || key == "delete" ? Color.accentColor : Color.secondary) : nil)
                        .accessibilityLabel(voiceLabels[key] ?? (key == "delete" ? "Xóa một chữ số" : key == "000" ? "Ba số không" : key))
                        .accessibilityIdentifier("keypad.\(key)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bàn phím số tiền")
    }
}

struct SelectionChip: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let icon { Image(systemName: icon).accessibilityHidden(true) }
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    if selected { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(selected ? Color.accentColor : Color.secondary)
        .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
