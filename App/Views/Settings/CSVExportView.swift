import SwiftData
import SwiftUI

struct CSVExportView: View {
    @Environment(\.modelContext) private var context
    @State private var from = ReportingMonth().interval.start
    @State private var to = Date()
    @State private var url: URL?
    @State private var error: String?
    @Query private var transactions: [Transaction]
    private var count: Int {
        guard let range = try? CSVExporter.range(from: from, to: to) else { return 0 }
        return transactions.filter { $0.date >= range.start && $0.date < range.end }.count
    }
    var body: some View {
        Form {
            Illustration(name: "illus-export-csv")
            Section("Khoảng ngày") {
                Button("Tháng này") { from = ReportingMonth().interval.start; to = ReportingMonth().interval.end.addingTimeInterval(-1); url = nil }.frame(minHeight: 44)
                Button("Tháng trước") { if let month = ReportingMonth().previous { from = month.interval.start; to = month.interval.end.addingTimeInterval(-1); url = nil } }.frame(minHeight: 44)
                Button("Năm nay") { from = LocalCalendar.calendar.date(from: DateComponents(year: ReportingMonth().year, month: 1, day: 1))!; to = Date(); url = nil }.frame(minHeight: 44)
                DatePicker("Từ ngày", selection: $from, displayedComponents: .date).frame(minHeight: 44)
                DatePicker("Đến ngày", selection: $to, displayedComponents: .date).frame(minHeight: 44)
            }
            Text("Sẽ xuất \(count) giao dịch.")
            Button("Xuất") {
                do { url = try CSVExporter.write(CSVExporter.csv(transactions: transactions, from: from, to: to), range: CSVExporter.range(from: from, to: to), now: Date()); error = nil }
                catch { self.error = error.localizedDescription }
            }.frame(minHeight: 44)
            if let url { ShareLink("Chia sẻ CSV", item: url).frame(minHeight: 44) }
            if let error { Text(error).foregroundStyle(.red) }
            Callout(level: .info, title: "Không dùng để khôi phục", message: "CSV chứa dữ liệu dạng chữ trong thư mục tạm, không được mã hóa. Chỉ chia sẻ với người bạn chọn.")
        }.navigationTitle("Xuất CSV")
        .onAppear { try? CSVExporter.cleanTemporaryFiles(); url = nil }
        .onChange(of: from) { _, _ in url = nil }.onChange(of: to) { _, _ in url = nil }
    }
}
