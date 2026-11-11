import Charts
import SwiftUI

struct StatsCategoryChart: View {
    let slices: [StatsService.CategoryTotal]
    let total: Int64
    private let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .secondary]
    var body: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
            SectorMark(angle: .value("Chi", StatsService.plotValue(slice.amount)), innerRadius: .ratio(0.6))
                .foregroundStyle(colors[index % colors.count])
                .accessibilityLabel(slice.name)
                .accessibilityValue("\(MoneyFormatter.string(from: slice.amount).replacingOccurrences(of: "₫", with: "đồng")), \(slice.percentageText)")
        }
        .frame(height: 200)
        .chartBackground { _ in
            Text(MoneyFormatter.string(from: total)).font(.caption).monospacedDigit()
                .multilineTextAlignment(.center).frame(width: 110)
                .minimumScaleFactor(0.5).accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                Label("\(slice.name), \(slice.percentageText)", systemImage: "circle.fill")
                    .foregroundStyle(colors[index % colors.count])
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
