import SwiftUI
import WidgetKit

// K1: the widget reads only `WidgetSnapshot` (a small JSON summary the app writes into the
// App Group). It never opens the SwiftData store. Without an App Group (Simulator, unsigned
// build, SideStore not granting groups) it falls back to quick actions, exactly like K0.
// Amounts appear only when "Hiện số tiền trên widget" is on in Settings; otherwise percentages.

// MARK: - Timeline

struct QuickEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date(), snapshot: WidgetPreviewData.snapshot) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(QuickEntry(date: Date(), snapshot: context.isPreview ? WidgetPreviewData.snapshot : SharedContainer.read()))
    }
    /// The app reloads timelines after each change; otherwise refresh at local midnight so
    /// yesterday's per-day figure is marked as stale.
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        let now = Date()
        let midnight = WidgetStyle.calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [QuickEntry(date: now, snapshot: SharedContainer.read())], policy: .after(midnight)))
    }
}

enum WidgetPreviewData {
    static var snapshot: WidgetSnapshot {
        var value = WidgetSnapshot(generatedAt: Date(), day: WidgetStyle.calendar.startOfDay(for: Date()), cycleName: "tháng 11",
                                   daysLeft: 12, showsAmounts: true, budgetFraction: 0.62, budgetLevel: 0)
        value.totalBalance = 12_450_000; value.todayLeft = 185_000; value.perDay = 240_000
        value.spentToday = 55_000; value.cycleSpent = 6_200_000; value.cycleLimit = 10_000_000
        return value
    }
}

// MARK: - Style

enum WidgetStyle {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Saigon")!
        calendar.locale = Locale(identifier: "vi_VN")
        return calendar
    }
    static let expense = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let income = Color(red: 0.13, green: 0.65, blue: 0.42)
    static let transfer = Color(red: 0.20, green: 0.47, blue: 0.95)
    static let stats = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let brandTop = Color(red: 0.11, green: 0.60, blue: 0.47)
    static let brandBottom = Color(red: 0.05, green: 0.38, blue: 0.36)

    static func weekday(_ date: Date) -> String {
        ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][calendar.component(.weekday, from: date) - 1]
    }
    static func dayMonth(_ date: Date) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return String(format: "%02d/%02d", parts.day!, parts.month!)
    }
    static func spoken(_ amount: Int64) -> String { MoneyFormatter.string(from: amount).replacingOccurrences(of: "₫", with: "đồng") }
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    static func levelColor(_ level: Int?) -> Color { level == 2 ? expense : level == 1 ? warning : .white }
}

enum QuickAction: CaseIterable, Identifiable {
    case expense, income, transfer, stats
    var id: Self { self }
    var title: String { switch self { case .expense: "Chi"; case .income: "Thu"; case .transfer: "Chuyển"; case .stats: "Thống kê" } }
    var symbol: String { switch self { case .expense: "minus"; case .income: "plus"; case .transfer: "arrow.left.arrow.right"; case .stats: "chart.bar.fill" } }
    var tint: Color { switch self { case .expense: WidgetStyle.expense; case .income: WidgetStyle.income; case .transfer: WidgetStyle.transfer; case .stats: WidgetStyle.stats } }
    var url: URL {
        switch self {
        case .expense: URL(string: "savemoney://add?kind=expense")!
        case .income: URL(string: "savemoney://add?kind=income")!
        case .transfer: URL(string: "savemoney://transfer")!
        case .stats: URL(string: "savemoney://stats")!
        }
    }
    var spoken: String { switch self { case .expense: "Thêm khoản chi"; case .income: "Thêm khoản thu"; case .transfer: "Chuyển tiền"; case .stats: "Mở thống kê" } }
}

/// What the main figure of a widget says, given the snapshot and privacy setting.
struct Headline {
    let caption: String
    let value: String
    let detail: String?
    let tint: Color
    let spoken: String

    init?(_ snapshot: WidgetSnapshot?, now: Date) {
        guard let snapshot else { return nil }
        let current = snapshot.isCurrent(now: now, calendar: WidgetStyle.calendar)
        if snapshot.showsAmounts, current, let left = snapshot.todayLeft, let perDay = snapshot.perDay {
            caption = left >= 0 ? "Hôm nay còn" : "Hôm nay vượt"
            value = MoneyFormatter.compact(abs(left))
            detail = "≈\(MoneyFormatter.compact(perDay))/ngày · còn \(snapshot.daysLeft) ngày"
            tint = left < 0 ? WidgetStyle.expense : .white
            spoken = (left >= 0 ? "Hôm nay còn được tiêu " : "Hôm nay đã vượt ") + WidgetStyle.spoken(abs(left))
        } else if let fraction = snapshot.budgetFraction {
            caption = "Ngân sách \(snapshot.cycleName)"
            value = WidgetStyle.percent(fraction)
            detail = current ? "đã dùng · còn \(snapshot.daysLeft) ngày" : "Mở app để cập nhật"
            tint = WidgetStyle.levelColor(snapshot.budgetLevel)
            spoken = "Đã dùng \(WidgetStyle.percent(fraction)) ngân sách \(snapshot.cycleName)"
        } else if snapshot.showsAmounts, let balance = snapshot.totalBalance {
            caption = "Tổng số dư"
            value = MoneyFormatter.compact(balance)
            detail = current ? snapshot.spentToday.map { "Hôm nay đã chi \(MoneyFormatter.compact($0))" } : "Mở app để cập nhật"
            tint = .white
            spoken = "Tổng số dư " + WidgetStyle.spoken(balance)
        } else {
            return nil
        }
    }
}

// MARK: - Home screen

struct QuickWidgetView: View {
    let entry: QuickEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var isFullColor: Bool { renderingMode == .fullColor }
    private var foreground: Color { isFullColor ? .white : .primary }
    private var headline: Headline? { Headline(entry.snapshot, now: entry.date) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .foregroundStyle(foreground)
        .containerBackground(for: .widget) {
            if isFullColor {
                LinearGradient(colors: [WidgetStyle.brandTop, WidgetStyle.brandBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else { Color.clear }
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetStyle.weekday(entry.date)).font(.caption.weight(.semibold)).opacity(0.85)
                Text(WidgetStyle.dayMonth(entry.date)).font(.title3.weight(.bold)).monospacedDigit()
            }
            Spacer(minLength: 4)
            Image(systemName: "dongsign.circle.fill").font(.title3).opacity(0.9).widgetAccentable().accessibilityHidden(true)
        }
    }

    private func headlineBlock(_ headline: Headline, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline.caption).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
            Text(headline.value).font(.system(large ? .largeTitle : .title, design: .rounded).bold()).monospacedDigit()
                .foregroundStyle(isFullColor ? headline.tint : .primary).lineLimit(1).minimumScaleFactor(0.5).widgetAccentable()
            if let detail = headline.detail { Text(detail).font(.caption2).opacity(0.85).lineLimit(2).minimumScaleFactor(0.8) }
        }
    }

    private func budgetBar(_ fraction: Double, level: Int?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(foreground.opacity(0.25))
                Capsule().fill(isFullColor ? WidgetStyle.levelColor(level) : .primary).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
        .widgetAccentable()
        .accessibilityHidden(true)
    }

    /// Small widgets are one tap target: the whole tile adds an expense.
    @ViewBuilder private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headline {
                HStack {
                    Text(entry.snapshot?.cycleName.capitalizedFirstLetter ?? "SaveMoney").font(.caption2.weight(.semibold)).opacity(0.85).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "plus.circle.fill").font(.title3).widgetAccentable().accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                headlineBlock(headline, large: false)
                if let fraction = entry.snapshot?.budgetFraction, entry.snapshot?.showsAmounts == true {
                    budgetBar(fraction, level: entry.snapshot?.budgetLevel).padding(.top, 6)
                }
            } else {
                dateHeader
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.headline.weight(.bold)).frame(width: 30, height: 30)
                        .background(isFullColor ? Color.white : Color.primary.opacity(0.15), in: Circle())
                        .foregroundStyle(isFullColor ? WidgetStyle.brandBottom : Color.primary).widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Ghi chi tiêu").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text("Chạm để thêm").font(.caption2).opacity(0.8)
                    }
                }
            }
        }
        .widgetURL(QuickAction.expense.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline.map { "SaveMoney. \($0.spoken). Chạm để thêm khoản chi" }
                            ?? "SaveMoney, \(WidgetStyle.weekday(entry.date)) \(WidgetStyle.dayMonth(entry.date)). Thêm khoản chi")
    }

    @ViewBuilder private var medium: some View {
        if let headline, let snapshot = entry.snapshot {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    headlineBlock(headline, large: false)
                    Spacer(minLength: 0)
                    if let fraction = snapshot.budgetFraction {
                        budgetBar(fraction, level: snapshot.budgetLevel)
                        Text(snapshot.showsAmounts && snapshot.cycleSpent != nil && snapshot.cycleLimit != nil
                             ? "\(MoneyFormatter.compact(snapshot.cycleSpent!)) / \(MoneyFormatter.compact(snapshot.cycleLimit!))"
                             : "\(WidgetStyle.percent(fraction)) ngân sách")
                            .font(.caption2).monospacedDigit().opacity(0.85)
                    } else if snapshot.showsAmounts, let balance = snapshot.totalBalance {
                        Text("Số dư \(MoneyFormatter.compact(balance))").font(.caption2).monospacedDigit().opacity(0.85)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headline.spoken)
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { tileLink(.expense); tileLink(.income) }
                    GridRow { tileLink(.transfer); tileLink(.stats) }
                }
                .frame(maxWidth: 150)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                dateHeader
                HStack(spacing: 8) { ForEach(QuickAction.allCases) { tileLink($0) } }
            }
        }
    }

    private func tileLink(_ action: QuickAction) -> some View {
        Link(destination: action.url) {
            VStack(spacing: 3) {
                Image(systemName: action.symbol).font(.subheadline.weight(.bold)).frame(width: 28, height: 28)
                    .background(isFullColor ? action.tint : Color.primary.opacity(0.15), in: Circle())
                    .foregroundStyle(Color.white).widgetAccentable()
                Text(action.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(isFullColor ? Color.black.opacity(0.8) : Color.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isFullColor ? Color.white.opacity(0.92) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(action.spoken)
    }
}

// MARK: - Lock screen (never shows amounts, whatever the setting)

struct LockWidgetView: View {
    let entry: QuickEntry
    @Environment(\.widgetFamily) private var family
    private var fraction: Double? { entry.snapshot?.budgetFraction }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                if let fraction {
                    Gauge(value: min(1, fraction)) { Image(systemName: "dongsign") } currentValueLabel: { Text(WidgetStyle.percent(fraction)).monospacedDigit() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .widgetAccentable()
                } else {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: "plus").font(.title3.weight(.bold))
                            Text("Chi").font(.caption2.weight(.semibold))
                        }
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").widgetAccentable()
                        Text("Ghi chi tiêu").font(.headline).lineLimit(1)
                    }
                    if let fraction, let snapshot = entry.snapshot {
                        Gauge(value: min(1, fraction)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                        Text("\(WidgetStyle.percent(fraction)) ngân sách · còn \(snapshot.daysLeft) ngày").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("SaveMoney · \(WidgetStyle.dayMonth(entry.date))").font(.caption).lineLimit(1)
                    }
                }
            default:
                if let fraction { Text("SaveMoney · \(WidgetStyle.percent(fraction)) ngân sách") } else { Label("Ghi chi tiêu", systemImage: "plus.circle") }
            }
        }
        .widgetURL(QuickAction.expense.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fraction.map { "SaveMoney, đã dùng \(WidgetStyle.percent($0)) ngân sách. Chạm để thêm khoản chi" } ?? "SaveMoney, thêm khoản chi")
        .containerBackground(.clear, for: .widget)
    }
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Widgets

struct SaveMoneyQuickWidget: Widget {
    // Same kind as the K0 probe so widgets already on the home screen keep working.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SaveMoneyWidgetTrial", provider: QuickProvider()) { entry in QuickWidgetView(entry: entry) }
            .configurationDisplayName("SaveMoney")
            .description("Hôm nay còn được tiêu bao nhiêu, ngân sách kỳ lương và nút ghi nhanh.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SaveMoneyLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SaveMoneyLockQuickAdd", provider: QuickProvider()) { entry in LockWidgetView(entry: entry) }
            .configurationDisplayName("SaveMoney — Màn hình khóa")
            .description("Phần trăm ngân sách và nút ghi chi. Không hiện số tiền trên màn hình khóa.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SaveMoneyWidgets: WidgetBundle {
    var body: some Widget {
        SaveMoneyQuickWidget()
        SaveMoneyLockWidget()
    }
}

// MARK: - Previews

private var hiddenAmounts: WidgetSnapshot {
    var value = WidgetPreviewData.snapshot
    value.showsAmounts = false; value.totalBalance = nil; value.todayLeft = nil; value.perDay = nil
    value.spentToday = nil; value.cycleSpent = nil; value.cycleLimit = nil
    return value
}

#Preview("Nhỏ — có số", as: .systemSmall) { SaveMoneyQuickWidget() } timeline: { QuickEntry(date: Date(), snapshot: WidgetPreviewData.snapshot) }
#Preview("Nhỏ — ẩn số", as: .systemSmall) { SaveMoneyQuickWidget() } timeline: { QuickEntry(date: Date(), snapshot: hiddenAmounts) }
#Preview("Nhỏ — chưa có App Group", as: .systemSmall) { SaveMoneyQuickWidget() } timeline: { QuickEntry(date: Date(), snapshot: nil) }
#Preview("Vừa — có số", as: .systemMedium) { SaveMoneyQuickWidget() } timeline: { QuickEntry(date: Date(), snapshot: WidgetPreviewData.snapshot) }
#Preview("Vừa — chưa có App Group", as: .systemMedium) { SaveMoneyQuickWidget() } timeline: { QuickEntry(date: Date(), snapshot: nil) }
#Preview("Khóa — chữ nhật", as: .accessoryRectangular) { SaveMoneyLockWidget() } timeline: { QuickEntry(date: Date(), snapshot: hiddenAmounts) }
#Preview("Khóa — tròn", as: .accessoryCircular) { SaveMoneyLockWidget() } timeline: { QuickEntry(date: Date(), snapshot: hiddenAmounts) }
