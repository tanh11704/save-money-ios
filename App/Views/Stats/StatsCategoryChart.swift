import Charts
import SwiftUI

struct StatsCategoryChart: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let slices: [StatsService.CategoryTotal]
    let total: Int64
    var body: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
            SectorMark(angle: .value("Chi", StatsService.plotValue(slice.amount)), innerRadius: .ratio(0.6))
                .foregroundStyle(CategoryStyle.tint(for: slice.icon))
                .accessibilityLabel(slice.name)
                .accessibilityValue("\(MoneyFormatter.string(from: slice.amount).replacingOccurrences(of: "₫", with: "đồng")), \(slice.percentageText)")
        }
        .frame(height: typeSize.isAccessibilitySize ? 280 : 200)
        .chartBackground { _ in
            Text(typeSize.isAccessibilitySize ? "Tổng chi" : MoneyFormatter.string(from: total)).font(.caption).monospacedDigit()
                .multilineTextAlignment(.center).frame(width: typeSize.isAccessibilitySize ? 140 : 110)
                .minimumScaleFactor(0.5).accessibilityHidden(true)
        }
        if typeSize.isAccessibilitySize { Text(MoneyFormatter.string(from: total)).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
    }
}
