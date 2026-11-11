import SwiftUI

@MainActor
struct TransactionRow: View {
    let transaction: Transaction
    var debt: DebtPresentation.Label? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { icon; texts(lineLimit: nil) }
                    amount(transaction)
                }
            } else {
                // Fixed layout: the amount always owns the trailing edge of the first line,
                // long titles truncate instead of pushing the amount to its own line.
                HStack(alignment: .top, spacing: 12) {
                    icon
                    texts(lineLimit: 1)
                    Spacer(minLength: 8)
                    amount(transaction).layoutPriority(1)
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
    }

    private var isPaidOnBehalf: Bool {
        transaction.kindRaw == TransactionKind.expense.rawValue && transaction.wallet?.isPerson == true
    }

    private var title: String {
        if let debt { return debt.title }
        if isPaidOnBehalf { return transaction.category?.name ?? "Chi tiêu" }
        return TransactionPresentation.title(transaction)
    }

    /// One secondary line: who paid / which wallet, then the note. Never repeats the title.
    private var subtitle: String {
        let source: String?
        if isPaidOnBehalf { source = "\(transaction.wallet?.name ?? "") trả hộ" }
        else if debt != nil { source = [transaction.wallet, transaction.toWallet].compactMap { $0 }.first { $0.isOwn }?.name }
        else if let adjustment = TransactionPresentation.adjustment(transaction) { source = adjustment.wallet?.name }
        else if transaction.kindRaw == TransactionKind.transfer.rawValue { source = nil } // title already reads "A → B"
        else { source = transaction.wallet?.name }
        return [debt?.detail, source, transaction.note.isEmpty ? nil : transaction.note]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var icon: some View {
        CategoryIcon(icon: TransactionPresentation.isAdjustment(transaction) ? "slider.horizontal.3"
                     : transaction.kindRaw == "transfer" ? "arrow.left.arrow.right" : transaction.category?.icon ?? "tag")
    }

    private func texts(lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold).foregroundStyle(.primary)
                .lineLimit(lineLimit).truncationMode(.tail)
            HStack(spacing: 4) {
                if transaction.recurrenceKey != nil {
                    Image(systemName: "arrow.triangle.2.circlepath").accessibilityLabel("Định kỳ")
                }
                if !subtitle.isEmpty { Text(subtitle).lineLimit(lineLimit).truncationMode(.tail) }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func amount(_ transaction: Transaction) -> some View {
        AmountText(amount: transaction.amount, kind: TransactionPresentation.isAdjustment(transaction) ? nil : TransactionKind(rawValue: transaction.kindRaw),
                   prefix: TransactionPresentation.adjustment(transaction).map { $0.increased ? "+" : "−" } ?? "")
            .lineLimit(1)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.5 : 1)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }

}
