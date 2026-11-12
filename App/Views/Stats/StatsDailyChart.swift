import Charts
import SwiftUI

struct StatsDailyChart: View {
    let days: [StatsService.DailyTotal]
    /// The period shown; weeks get weekday labels and future days are shaded.
    var period: StatsPeriod? = nil
    let allowance: Int64?
    @State private var selectedDay: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var axisFontSize: CGFloat = 12

    init(days: [StatsService.DailyTotal], period: StatsPeriod? = nil, allowance: Int64?) {
        self.days = days; self.period = period; self.allowance = allowance
    }

    /// Kept for previews/tests that build a monthly chart directly.
    init(days: [StatsService.DailyTotal], month: ReportingMonth?, allowance: Int64?) {
        self.init(days: days, period: month.map { StatsPeriod(month: $0) }, allowance: allowance)
    }

    private var isWeek: Bool { period?.kind == .week }

    /// 1-based index of today inside the period, or nil when today is outside it.
    private var todayIndex: Int? {
        guard let period, period.contains(Date()) else { return nil }
        let calendar = LocalCalendar.calendar
        return calendar.dateComponents([.day], from: period.interval.start, to: calendar.startOfDay(for: Date())).day! + 1
    }

    private var ticks: [Int] {
        if isWeek { return days.map(\.day) }
        guard !days.isEmpty else { return [] }
        return typeSize.isAccessibilitySize ? Array(Set([1, 10, 20, days.count])).filter { $0 <= days.count }.sorted() : Array(stride(from: 1, through: days.count, by: 5))
    }

    private func label(for day: Int) -> String {
        guard let entry = days.first(where: { $0.day == day }), entry.date != .distantPast else { return String(day) }
        // Payday cycles cross months, so label the calendar day ("25", "1") rather than the position.
        return isWeek ? StatsPeriod.weekdayLabel(entry.date) : String(LocalCalendar.calendar.component(.day, from: entry.date))
    }

    private func spokenDay(_ day: StatsService.DailyTotal) -> String {
        if isWeek { return "\(StatsPeriod.weekdayLabel(day.date)) \(StatsPeriod.dayMonth(day.date))" }
        guard day.date != .distantPast else { return "Ngày \(day.day)" }
        return MonthCycle.isCalendarMonth ? "Ngày \(LocalCalendar.calendar.component(.day, from: day.date))" : "Ngày \(StatsPeriod.dayMonth(day.date))"
    }

    var body: some View {
        Chart {
            if let today = todayIndex, today < days.count {
                // Future days are shaded instead of looking like zero-spend days.
                RectangleMark(xStart: .value("Từ", Double(today) + 0.5), xEnd: .value("Đến", Double(days.count) + 1))
                    .foregroundStyle(Color.secondary.opacity(0.08))
                    .accessibilityHidden(true)
            }
            ForEach(days) { day in
                BarMark(x: .value("Ngày", day.day), y: .value("Chi", day.plotValue), width: isWeek ? .ratio(0.6) : .automatic)
                    .foregroundStyle(Color.accentColor.opacity(todayIndex.map { day.day > $0 } == true ? 0.25 : 1))
                    .cornerRadius(isWeek ? 6 : 2)
                    .accessibilityLabel(spokenDay(day))
                    .accessibilityValue(MoneyFormatter.string(from: day.expense).replacingOccurrences(of: "₫", with: "đồng"))
            }
            if let allowance {
                RuleMark(y: .value("Trung bình cho phép/ngày", StatsService.plotValue(allowance)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("≈\(MoneyFormatter.compact(allowance))/ngày").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Trung bình cho phép/ngày")
                    .accessibilityValue(MoneyFormatter.string(from: allowance).replacingOccurrences(of: "₫", with: "đồng"))
            }
            if let selectedDay, let day = days.first(where: { $0.day == selectedDay }) {
                RuleMark(x: .value("Ngày chọn", selectedDay))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(spokenDay(day)): \(MoneyFormatter.string(from: day.expense))").font(.caption).monospacedDigit()
                            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXScale(domain: 0...(days.count + 1))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                if !isWeek { AxisGridLine() }
                AxisTick()
                AxisValueLabel(anchor: isWeek ? .top : value.as(Int.self) == days.count ? .topTrailing : value.as(Int.self) == 1 ? .topLeading : .top,
                               collisionResolution: .disabled) {
                    if let day = value.as(Int.self) { Text(label(for: day)).font(.system(size: min(axisFontSize, 22))) }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Int64.self) { Text(MoneyFormatter.compact(amount)).font(.system(size: min(axisFontSize, 22))) }
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 260 : 180)
    }
}

/// Income vs expense for the last N weeks or months; tapping a column selects that period.
struct StatsTrendChart: View {
    let points: [StatsService.PeriodTotal]
    let selected: StatsPeriod
    let onSelect: (StatsPeriod) -> Void
    @State private var rawSelection: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var axisFontSize: CGFloat = 12

    private func key(_ period: StatsPeriod) -> String { period.shortTitle }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Kỳ", key(point.period)), y: .value("Số tiền", StatsService.plotValue(point.expense)))
                        .foregroundStyle(by: .value("Loại", "Chi"))
                        .position(by: .value("Loại", "Chi"))
                        .opacity(point.period == selected ? 1 : 0.55)
                        .cornerRadius(3)
                        .accessibilityLabel("\(point.period.title), chi")
                        .accessibilityValue(MoneyFormatter.string(from: point.expense).replacingOccurrences(of: "₫", with: "đồng"))
                    BarMark(x: .value("Kỳ", key(point.period)), y: .value("Số tiền", StatsService.plotValue(point.income)))
                        .foregroundStyle(by: .value("Loại", "Thu"))
                        .position(by: .value("Loại", "Thu"))
                        .opacity(point.period == selected ? 1 : 0.55)
                        .cornerRadius(3)
                        .accessibilityLabel("\(point.period.title), thu")
                        .accessibilityValue(MoneyFormatter.string(from: point.income).replacingOccurrences(of: "₫", with: "đồng"))
                }
            }
            .chartForegroundStyleScale(["Chi": Color("Expense"), "Thu": Color("Income")])
            .chartLegend(position: .top, alignment: .leading)
            .chartXSelection(value: $rawSelection)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let text = value.as(String.self) {
                            Text(text).font(.system(size: min(axisFontSize, 20)))
                                .fontWeight(text == key(selected) ? .bold : .regular)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Int64.self) { Text(MoneyFormatter.compact(amount)).font(.system(size: min(axisFontSize, 20))) }
                    }
                }
            }
            .frame(height: typeSize.isAccessibilitySize ? 260 : 190)
            .onChange(of: rawSelection) { _, value in
                guard let value, let point = points.first(where: { key($0.period) == value }) else { return }
                onSelect(point.period)
                rawSelection = nil
            }
            Text("Chạm một cột để xem kỳ đó").font(.caption).foregroundStyle(.secondary)
        }
    }
}
