import SwiftUI

@MainActor
struct TransactionRow: View {
    let transaction: Transaction
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    description(transaction)
                    amount(transaction)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        description(transaction)
                        Spacer(minLength: 8)
                        amount(transaction)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        description(transaction)
                        amount(transaction)
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
    }

    private func description(_ transaction: Transaction) -> some View {
        HStack(alignment: .top, spacing: 8) {
            CategoryIcon(icon: transaction.kindRaw == "transfer" ? "arrow.left.arrow.right" : transaction.category?.icon ?? "tag")
            VStack(alignment: .leading, spacing: 4) {
                Text(TransactionPresentation.title(transaction)).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if transaction.recurrenceKey != nil {
                    Label("Định kỳ", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                }
                Text(transaction.wallet?.name ?? "Ví không xác định")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !transaction.note.isEmpty {
                    Text(transaction.note).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func amount(_ transaction: Transaction) -> some View {
        AmountText(amount: transaction.amount, kind: TransactionKind(rawValue: transaction.kindRaw))
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            .minimumScaleFactor(0.25)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

}
