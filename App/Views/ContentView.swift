import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wallet.bifold")
                .font(.largeTitle)
            Text("SaveMoney")
                .font(.title)
            Text("Ứng dụng đang được thiết lập.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

