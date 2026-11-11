import SwiftData
import SwiftUI

@MainActor
struct StatsCategoryDetailView: View {
    let period: StatsPeriod
    let key: StatsService.CategoryKey
    init(period: StatsPeriod, key: StatsService.CategoryKey) { self.period = period; self.key = key }
    init(month: ReportingMonth, key: StatsService.CategoryKey) { self.init(period: StatsPeriod(month: month), key: key) }
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var body: some View {
        let result = Result { try StatsService.report(period: period, transactions: transactions) }
        List {
            switch result {
            case .success(let report):
                let row = report.rows(for: key.kind).first { $0.key == key }
                let details = report.transactions(for: key)
                Section {
                    Text(row?.name ?? "Không có giao dịch").font(.headline)
                    Text(period.title).foregroundStyle(.secondary)
                    Text(MoneyFormatter.string(from: row?.amount ?? 0)).font(.title2).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if details.isEmpty { Text(period.kind == .week ? "Không có giao dịch trong tuần này." : "Không có giao dịch trong tháng này.").foregroundStyle(.secondary) }
                ForEach(TransactionGrouping.group(details)) { day in
                    Section(TransactionGrouping.title(for: day.date)) {
                        ForEach(day.transactions, id: \.id) { transaction in
                            TransactionRow(transaction: transaction)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(TransactionPresentation.accessibilityLabel(transaction))
                                .accessibilityValue([transaction.wallet?.name ?? "", transaction.note].filter { !$0.isEmpty }.joined(separator: ", "))
                        }
                    }
                }
            case .failure(let error):
                Text(TransactionPresentation.errorMessage(error)).foregroundStyle(.red)
            }
        }
        .navigationTitle("Giao dịch danh mục")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { dismiss() } } }
    }
}
