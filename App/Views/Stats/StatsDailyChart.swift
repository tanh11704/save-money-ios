import Charts
import SwiftUI

struct StatsDailyChart: View {
    let days: [StatsService.DailyTotal]
    let allowance: Int64?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var ticks: [Int] {
        typeSize.isAccessibilitySize ? Array(Set([1, 10, 20, days.count])).sorted() : Array(stride(from: 1, through: days.count, by: 5))
    }
    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Ngày", day.day), y: .value("Chi", day.plotValue))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Ngày \(day.day)")
                    .accessibilityValue(MoneyFormatter.string(from: day.expense).replacingOccurrences(of: "₫", with: "đồng"))
            }
            if let allowance {
                RuleMark(y: .value("Trung bình cho phép/ngày", StatsService.plotValue(allowance)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Trung bình cho phép/ngày")
                    .accessibilityValue(MoneyFormatter.string(from: allowance).replacingOccurrences(of: "₫", with: "đồng"))
            }
        }
        .chartXAxis { AxisMarks(values: ticks) }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Int64.self) { Text(MoneyFormatter.compact(amount)) }
                }
            }
        }
        .frame(height: 180)
        if let allowance {
            Text("Trung bình cho phép/ngày: \(MoneyFormatter.string(from: allowance))")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
