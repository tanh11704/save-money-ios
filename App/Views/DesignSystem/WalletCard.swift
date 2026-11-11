import SwiftUI

struct WalletCard: View {
    let wallet: Wallet
    let balance: Int64?
    @Environment(\.colorSchemeContrast) private var contrast
    private var tint: Color {
        switch WalletKind(rawValue: wallet.kindRaw) ?? .other {
        case .cash: return Color("Income")
        case .bank: return Color("Transfer")
        case .card: return .purple
        case .person: return CategoryStyle.tint(for: "person.crop.circle")
        case .other: return .secondary
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon).accessibilityHidden(true)
                Text(wallet.name).fixedSize(horizontal: false, vertical: true)
            }.font(.headline)
            if let balance {
                AmountText(amount: balance, style: .system(.title, design: .rounded).bold())
                if balance < 0 { Label("Đang nợ", systemImage: "exclamationmark.circle").font(.caption) }
            } else { Text("Chưa tính được số dư") }
        }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(16)
            .background(LinearGradient(colors: [tint.opacity(contrast == .increased ? 0 : 0.2), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomTrailing) {
                if contrast != .increased {
                    Image(systemName: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon).font(.system(size: 64)).foregroundStyle(tint.opacity(0.08)).padding(12).accessibilityHidden(true).allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint, lineWidth: contrast == .increased ? 2 : 0.5))
            .accessibilityElement(children: .combine)
    }
}
