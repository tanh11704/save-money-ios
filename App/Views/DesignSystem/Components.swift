import SwiftUI
import UIKit

enum Spacing { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24 }
enum CategoryStyle { static func tint(for icon: String) -> Color { Color("CategoryTint\(CategoryPalette.index(for: icon))") } }

struct CategoryIcon: View {
    let icon: String
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(CategoryStyle.tint(for: icon), in: Circle()).accessibilityHidden(true)
    }
}
struct AmountText: View {
    let amount: Int64
    var kind: TransactionKind? = nil
    var style: Font = .headline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: String {
        let formatted = MoneyFormatter.string(from: amount)
        guard amount >= 0 else { return formatted }
        switch kind { case .income: return "+" + formatted; case .expense: return "−" + formatted; default: return formatted }
    }
    var body: some View {
        Text(text).font(style).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
            .foregroundStyle(kind.map { Color($0 == .income ? "Income" : $0 == .expense ? "Expense" : "Transfer") } ?? .primary)
            .contentTransition(reduceMotion ? .identity : .numericText())
    }
}
struct Card<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { if contrast == .increased { RoundedRectangle(cornerRadius: 16).stroke(.secondary, lineWidth: 1) } }
    }
}
struct TrendBadge: View {
    let delta: String
    var body: some View { Text(delta).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()).accessibilityLabel(delta.replacingOccurrences(of: "▲", with: "Tăng").replacingOccurrences(of: "▼", with: "Giảm")) }
}
struct StatTile: View {
    let title: String, value: String, icon: String
    var trend: String? = nil
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
            if let trend { TrendBadge(delta: trend) }
        } }.accessibilityElement(children: .combine)
    }
}
struct Callout: View {
    enum Level { case info, warning, danger }
    let level: Level
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var expanded = false
    private var icon: String { level == .info ? "info.circle" : level == .warning ? "exclamationmark.triangle" : "xmark.octagon" }
    private var tint: Color { level == .info ? .accentColor : level == .warning ? .orange : .red }
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            if let message { DisclosureGroup("Chi tiết", isExpanded: $expanded) { Text(message).font(.subheadline).foregroundStyle(.secondary) } }
            if let actionTitle, let action { Button(actionTitle, action: action).frame(minHeight: 44) }
        } }
    }
}
struct InfoButton: View {
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Thông tin").popover(isPresented: $showing) {
                ScrollView { Text(text).padding().fixedSize(horizontal: false, vertical: true) }
                    .frame(idealWidth: 300, idealHeight: 220).presentationCompactAdaptation(.popover)
            }
    }
}
struct Illustration: View {
    let name: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if !typeSize.isAccessibilitySize, UIImage(named: name) != nil {
            Image(name).resizable().scaledToFit().frame(maxWidth: 200, maxHeight: 180).accessibilityHidden(true)
        }
    }
}
struct EmptyState: View {
    let image: String, title: String, message: String
    var symbol = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Illustration(name: image)
            Label(title, systemImage: symbol)
        } description: { Text(message) } actions: {
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).frame(minHeight: 44) }
        }
    }
}
struct ProgressRing: View {
    let fraction: Double
    var level: String? = nil
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            Circle().trim(from: 0, to: min(1, max(0, fraction))).stroke(fraction >= 1 ? Color.red : fraction >= 0.8 ? .orange : .accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack { Text(fraction, format: .percent.precision(.fractionLength(0))).font(.headline); if let level { Text(level).font(.caption) } }
        }.frame(width: 120, height: 120).accessibilityElement(children: .combine)
    }
}
struct IconRow: View {
    let icon: String
    var tint: Color = .accentColor
    let title: String
    var value: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 30, height: 30).background(tint, in: RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let value { Text(value).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(minHeight: 44)
    }
}
struct Toast: View {
    let message: String
    var icon = "checkmark.circle.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Label(message, systemImage: icon).font(.subheadline.bold()).padding().background(.regularMaterial, in: Capsule())
            .padding(.horizontal).accessibilityElement(children: .combine)
            .task { UIAccessibility.post(notification: .announcement, argument: message) }
    }
}
