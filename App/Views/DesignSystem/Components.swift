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
    var prefix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: String {
        let formatted = MoneyFormatter.string(from: amount)
        guard amount >= 0 else { return formatted }
        switch kind { case .income: return "+" + formatted; case .expense: return "−" + formatted; default: return formatted }
    }
    var body: some View {
        Text(prefix + text).font(style).monospacedDigit().lineLimit(1).minimumScaleFactor(0.25)
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
    private var visible: String {
        if delta.hasPrefix("Tăng ") { return "▲ " + delta.dropFirst(5) }
        if delta.hasPrefix("Giảm ") { return "▼ " + delta.dropFirst(5) }
        return delta
    }
    var body: some View { Text(visible).font(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs).background(.quaternary, in: Capsule()).accessibilityLabel(delta.replacingOccurrences(of: "▲", with: "Tăng").replacingOccurrences(of: "▼", with: "Giảm")) }
}
struct StatTile: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String, value: String, icon: String
    var trend: String? = nil
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
            Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
            if let trend { TrendBadge(delta: trend) }
        } }.accessibilityElement(children: .combine)
    }
}
struct Callout: View {
    enum Level { case info, warning, danger }
    let level: Level
    let title: String
    var symbol: String? = nil
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var expanded = false
    private var icon: String { symbol ?? (level == .info ? "info.circle" : level == .warning ? "exclamationmark.triangle" : "xmark.octagon") }
    private var tint: Color { level == .info ? .accentColor : level == .warning ? .orange : .red }
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) { Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true); Text(title).foregroundStyle(.primary) }.font(.headline)
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
            if let actionTitle, let action { Button(actionTitle, action: action).appProminentButton().frame(minHeight: 44) }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let icon: String
    var tint: Color = .accentColor
    let title: String
    var value: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 30, height: 30).background(tint, in: RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            Text(title).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let value { Text(value).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(minHeight: 44)
    }
}
struct Toast: View {
    let message: String
    var icon = "checkmark.circle.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    var body: some View {
        HStack {
            if reduceMotion { Image(systemName: icon).accessibilityHidden(true) }
            else { Image(systemName: icon).symbolEffect(.bounce, value: bounce).accessibilityHidden(true) }
            Text(message)
        }.font(.subheadline.bold()).padding().background(.regularMaterial, in: Capsule())
            .padding(.horizontal).accessibilityElement(children: .combine)
            .task { bounce = !reduceMotion; UIAccessibility.post(notification: .announcement, argument: message) }
    }
}


extension View {
    func appProminentButton() -> some View {
        buttonStyle(AppProminentButtonStyle())
    }

    /// Full-screen scroll content shares the grouped background used by lists.
    func appScreenBackground() -> some View {
        background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}


struct CalendarTile: View {
    let date: Date
    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", LocalCalendar.calendar.component(.day, from: date))).font(.title2.bold()).monospacedDigit()
            Text("TH\(LocalCalendar.calendar.component(.month, from: date))").font(.caption2.bold())
        }.padding(8).frame(minWidth: 52, minHeight: 60)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
    }
}


struct InlineError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle").font(.footnote)
            .foregroundStyle(Color("Expense")).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Lỗi, " + message)
    }
}


struct RestoreSuccessView: View {
    let transactionCount: Int
    let done: () -> Void
    var body: some View {
        Card { VStack(spacing: Spacing.m) {
            Illustration(name: "illus-restore-success")
            Label("Đã khôi phục", systemImage: "checkmark.circle.fill").font(.headline)
            Text("\(transactionCount) giao dịch. Số dư đã được kiểm tra.").font(.subheadline).multilineTextAlignment(.center)
            Button("Xong", action: done).appProminentButton().frame(minHeight: 44)
        }.frame(maxWidth: .infinity) }
    }
}


struct AppProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 44)
            .foregroundStyle(isEnabled ? Color("OnAccent") : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)))
            }
            .overlay {
                if !isEnabled || contrast == .increased {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(isEnabled ? 0.5 : 0.25), lineWidth: 1)
                }
            }
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
    }
}
