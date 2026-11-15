import Charts
import SwiftUI

/// Donut of expense categories. Tapping a slice shows it in the centre and offers its detail.
struct StatsCategoryChart: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let slices: [StatsService.CategoryTotal]
    let total: Int64
    var onOpen: ((StatsService.CategoryKey) -> Void)? = nil
    @State private var rawSelection: Double?
    @State private var selectedKey: StatsService.CategoryKey?

    private var selected: StatsService.CategoryTotal? { slices.first { $0.key == selectedKey } }

    /// The slice whose angular range contains `value` (Charts reports the cumulative plot value).
    private func slice(at value: Double) -> StatsService.CategoryTotal? {
        var cumulative = 0.0
        for slice in slices {
            cumulative += StatsService.plotValue(slice.amount)
            if value <= cumulative { return slice }
        }
        return slices.last
    }

    var body: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
            SectorMark(angle: .value("Chi", StatsService.plotValue(slice.amount)), innerRadius: .ratio(0.6),
                       outerRadius: .ratio(slice.key == selectedKey ? 1 : 0.92), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(CategoryStyle.tint(for: slice.icon))
                .opacity(selectedKey == nil || slice.key == selectedKey ? 1 : 0.4)
                .accessibilityLabel(slice.name)
                .accessibilityValue("\(MoneyFormatter.string(from: slice.amount).replacingOccurrences(of: "₫", with: "đồng")), \(slice.percentageText)")
        }
        .chartAngleSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, value in
            guard let value, let hit = slice(at: value) else { return }
            withAnimation(.snappy) { selectedKey = hit.key == selectedKey ? nil : hit.key }
        }
        .frame(height: typeSize.isAccessibilitySize ? 280 : 210)
        .chartBackground { _ in
            VStack(spacing: 2) {
                if let selected {
                    Text(selected.name).font(.caption.weight(.semibold)).lineLimit(2)
                    Text(MoneyFormatter.compact(selected.amount)).font(.headline).monospacedDigit()
                    Text(selected.percentageText).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Tổng chi").font(.caption).foregroundStyle(.secondary)
                    Text(typeSize.isAccessibilitySize ? "" : MoneyFormatter.compact(total)).font(.headline).monospacedDigit()
                }
            }
            .multilineTextAlignment(.center).frame(width: typeSize.isAccessibilitySize ? 140 : 110)
            .minimumScaleFactor(0.5).accessibilityHidden(true)
        }
        if typeSize.isAccessibilitySize { Text(MoneyFormatter.string(from: total)).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
        if let selected, !selected.key.isOther, let onOpen {
            Button { onOpen(selected.key) } label: {
                Label("Xem giao dịch \(selected.name)", systemImage: "arrow.right.circle").frame(maxWidth: .infinity, minHeight: 44)
            }
        } else if selectedKey == nil {
            Text("Chạm một phần của biểu đồ để xem chi tiết").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
    }
}
