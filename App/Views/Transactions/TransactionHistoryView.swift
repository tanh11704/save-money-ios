import SwiftUI

@MainActor
struct TransactionHistoryView: View {
    @ObservedObject var store: TransactionScreenStore

    var body: some View {
        Text("Lịch sử sẽ được nối ở bước 2c.")
            .foregroundStyle(.secondary)
            .padding()
            .navigationTitle("Lịch sử")
    }
}
