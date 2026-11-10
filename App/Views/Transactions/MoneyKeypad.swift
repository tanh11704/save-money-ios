import SwiftUI

struct MoneyKeypad: View {
    let press: (MoneyFormatter.Key) -> Void
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "delete"]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            if key == "delete" { press(.backspace) }
                            else if key == "000" { press(.tripleZero) }
                            else if let digit = Int(key) { press(.digit(digit)) }
                        } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left") }
                                else { Text(key).monospacedDigit() }
                            }
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(key == "delete" ? "Xóa một chữ số" : key == "000" ? "Ba số không" : key)
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
