import Charts
import SwiftUI

struct StatsDailyChart: View {
    let days: [StatsService.DailyTotal]
    var month: ReportingMonth? = nil
    let allowance: Int64?
    @State private var selectedDay: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var axisFontSize: CGFloat = 12
    private var ticks: [Int] {
        typeSize.isAccessibilitySize ? Array(Set([1, 10, 20, days.count])).sorted() : Array(stride(from: 1, through: days.count, by: 5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Ngày", day.day), y: .value("Chi", day.plotValue))
                    .foregroundStyle(Color.accentColor.opacity(month == ReportingMonth() && day.day > LocalCalendar.calendar.component(.day, from: Date()) ? 0.25 : 1))
                    .accessibilityLabel("Ngày \(day.day)")
                    .accessibilityValue(MoneyFormatter.string(from: day.expense).replacingOccurrences(of: "₫", with: "đồng"))
            }
            if let allowance {
                RuleMark(y: .value("Trung bình cho phép/ngày", StatsService.plotValue(allowance)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) { Text("Hạn mức/ngày").font(.caption2).foregroundStyle(.secondary) }
                    .accessibilityLabel("Trung bình cho phép/ngày")
                    .accessibilityValue(MoneyFormatter.string(from: allowance).replacingOccurrences(of: "₫", with: "đồng"))
            }
            if let selectedDay, let day = days.first(where: { $0.day == selectedDay }) {
                RuleMark(x: .value("Ngày chọn", selectedDay))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("Ngày \(day.day): \(MoneyFormatter.string(from: day.expense))").font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXScale(domain: 0...(days.count + 1))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine(); AxisTick()
                AxisValueLabel(anchor: value.as(Int.self) == days.count ? .topTrailing : value.as(Int.self) == 1 ? .topLeading : .top, collisionResolution: .disabled) {
                    if let day = value.as(Int.self) { Text(String(day)).font(.system(size: min(axisFontSize, 22))) }
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
        if let allowance {
            Text("Trung bình cho phép/ngày: \(MoneyFormatter.string(from: allowance))")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        }
    }
}
