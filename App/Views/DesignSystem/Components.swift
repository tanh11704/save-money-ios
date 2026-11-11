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
    var valueTint: Color = .primary
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
            Text(value).foregroundStyle(valueTint).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
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
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
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

/// Compact two-line financial row; accessibility sizes can expand vertically.
struct LedgerRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let amount: String
    var trailingSubtitle: String? = nil
    var progress: Double? = nil
    var tint: Color = .accentColor
    /// Draw the icon as a coloured category disc so rows match chart colours.
    var categoryIcon = false
    @Environment(\.dynamicTypeSize) private var typeSize

    @ViewBuilder private var iconView: some View {
        if categoryIcon { CategoryIcon(icon: icon, size: 32) }
        else { Image(systemName: icon).foregroundStyle(tint).frame(width: 32, height: 32).accessibilityHidden(true) }
    }

    private var leading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1) }
        }
    }
    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(amount).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
            if let trailingSubtitle { Text(trailingSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1) }
        }
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                iconView
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { leading; trailing }
                } else {
                    leading.layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let progress {
                ProgressView(value: min(1, max(0, progress))).tint(tint)
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            }
        }.frame(minHeight: 44).foregroundStyle(.primary)
            .accessibilityElement(children: .combine)
    }
}

/// Large, labelled Chi/Thu/Chuyển switcher. A segmented Picker in a navigation bar
/// collapses Labels to icons and limits height, so this stays in content space.
struct KindSelector: View {
    @Binding var kind: TransactionKind
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    static let items: [(kind: TransactionKind, title: String, icon: String)] = [
        (.expense, "Chi", "arrow.down.circle.fill"),
        (.income, "Thu", "arrow.up.circle.fill"),
        (.transfer, "Chuyển", "arrow.left.arrow.right.circle.fill"),
    ]

    static func colorName(_ kind: TransactionKind) -> String {
        switch kind { case .expense: "Expense"; case .income: "Income"; case .transfer: "Transfer" }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.items, id: \.kind) { item in
                let selected = kind == item.kind
                Button {
                    guard kind != item.kind else { return }
                    if reduceMotion { kind = item.kind } else { withAnimation(.snappy(duration: 0.25)) { kind = item.kind } }
                } label: {
                    HStack(spacing: 6) {
                        if !typeSize.isAccessibilitySize { Image(systemName: item.icon).imageScale(.medium) }
                        Text(item.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.headline)
                    .foregroundStyle(selected ? Color("OnAccent") : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 56 : 48)
                    .background {
                        if selected {
                            Capsule().fill(Color(Self.colorName(item.kind)))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("transaction.kind.\(item.kind.rawValue)")
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loại giao dịch")
        .accessibilityIdentifier("transaction.kind")
    }
}

// MARK: - Form inputs and sheets

/// Labelled text input: filled 52pt field, focus/error border, clear button, optional counter.
struct FormField<F: Hashable>: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var error: String? = nil
    var limit: Int? = nil
    var multiline = false
    var secure = false
    var submitLabel: SubmitLabel = .done
    let focus: FocusState<F?>.Binding
    let field: F
    var onSubmit: () -> Void = {}
    var identifier: String? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    private var isFocused: Bool { focus.wrappedValue == field }
    private var border: Color {
        if error != nil { return Color("Expense") }
        if isFocused { return .accentColor }
        return contrast == .increased ? .secondary : Color(uiColor: .separator).opacity(0.6)
    }

    @ViewBuilder private var input: some View {
        if secure {
            SecureField(prompt, text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        } else if multiline {
            TextField(prompt, text: $text, axis: .vertical).lineLimit(2...6)
        } else {
            TextField(prompt, text: $text).lineLimit(1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let limit {
                    Text("\(text.count)/\(limit)").font(.caption).monospacedDigit()
                        .foregroundStyle(text.count > limit ? Color("Expense") : Color.secondary)
                        .accessibilityLabel("\(text.count) trên \(limit) ký tự")
                }
            }
            HStack(alignment: multiline ? .top : .center, spacing: 8) {
                input
                    .focused(focus, equals: field)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier ?? "")
                if !text.isEmpty && isFocused {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).frame(minWidth: 28, minHeight: 28)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Xóa nội dung \(label)")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: isFocused || error != nil ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { focus.wrappedValue = field }
            if let error { InlineError(message: error) }
        }
    }
}

/// Small heading above a form group; consistent with FormField labels.
struct FieldLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Large tappable options (icon + title) replacing menu pickers for short lists.
struct ChoiceChips<Value: Hashable>: View {
    let options: [(value: Value, title: String, icon: String)]
    @Binding var selection: Value
    var disabled = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button { selection = option.value } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.icon).frame(width: 22).accessibilityHidden(true)
                        Text(option.title).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).accessibilityHidden(true) }
                    }
                    .font(.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled && !selected ? 0.5 : 1)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// Bottom bar with optional extra content (e.g. a keypad) above one prominent action.
struct PrimaryActionBar<Extra: View>: View {
    let title: String
    var systemImage: String = "checkmark"
    var enabled = true
    var identifier: String? = nil
    let action: () -> Void
    @ViewBuilder var extra: Extra
    var body: some View {
        VStack(spacing: Spacing.s) {
            extra
            Button(action: action) {
                Label(title, systemImage: systemImage).frame(maxWidth: .infinity, minHeight: 44)
            }
            .appProminentButton()
            .disabled(!enabled)
            .accessibilityIdentifier(identifier ?? "")
        }
        .padding(.horizontal)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .background(.bar)
    }
}
extension PrimaryActionBar where Extra == EmptyView {
    init(title: String, systemImage: String = "checkmark", enabled: Bool = true, identifier: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, enabled: enabled, identifier: identifier, action: action) { EmptyView() }
    }
}

enum SheetSize { case compact, medium, large }
extension View {
    /// Consistent sheet chrome: sized to content, visible grabber, rounded corners.
    func appSheet(_ size: SheetSize) -> some View {
        let detents: Set<PresentationDetent> = switch size {
            case .compact: [.height(340), .medium]
            case .medium: [.medium, .large]
            case .large: [.large]
        }
        return presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }
}
