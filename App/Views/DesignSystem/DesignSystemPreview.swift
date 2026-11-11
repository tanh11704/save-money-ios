#if DEBUG
import SwiftUI

private struct DesignSystemGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                HStack { ForEach(CategorySymbols.all.prefix(6)) { CategoryIcon(icon: $0.name) } }
                AmountText(amount: 1_250_000, kind: .expense, style: .system(.largeTitle, design: .rounded).bold())
                StatTile(title: "Thu tháng này", value: "2.000.000 ₫", icon: "arrow.up.circle", trend: "▲ 12,5%")
                Callout(level: .warning, title: "Sắp hết hạn mức", message: "Chi tiết hạn mức tháng này")
                HStack { ProgressRing(fraction: 0.85, level: "Sắp hết"); InfoButton(text: "Giải thích bổ sung") }
                IconRow(icon: "lock", title: "Mã hóa", value: "Đang bật")
                EmptyState(image: "illus-empty-history", title: "Chưa có giao dịch", message: "Ghi khoản đầu tiên", actionTitle: "Thêm") {}
                Toast(message: "Đã lưu")
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}
#Preview("Sáng") { DesignSystemGallery() }
#Preview("Tối") { DesignSystemGallery().preferredColorScheme(.dark) }
#Preview("AX5") { DesignSystemGallery().environment(\.dynamicTypeSize, .accessibility5) }
#endif
