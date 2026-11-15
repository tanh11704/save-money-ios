import SwiftUI

/// Own wallets are vivid gradient cards (colour chosen per wallet); people in the debt book keep
/// the quieter tinted card so they never look like money the user holds.
struct WalletCard: View {
    let wallet: Wallet
    let balance: Int64?
    var isMain = false
    @Environment(\.colorSchemeContrast) private var contrast
    private var kind: WalletKind { WalletKind(rawValue: wallet.kindRaw) ?? .other }

    var body: some View {
        if wallet.isOwn { ownCard } else { personCard }
    }

    private var ownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: kind.icon).font(.headline).accessibilityHidden(true)
                Text(wallet.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isMain {
                    Label("Ví chính", systemImage: "star.fill").font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            Text(kind.title).font(.caption).opacity(0.85)
            Spacer(minLength: 0)
            if let balance {
                AmountText(amount: balance, style: .system(.title, design: .rounded).bold(), tint: .white)
                if balance < 0 { Label("Đang nợ", systemImage: "exclamationmark.circle").font(.caption.weight(.semibold)) }
            } else { Text("Chưa tính được số dư") }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .padding(18)
        .background(WalletPalette.gradient(for: wallet), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if contrast != .increased {
                Image(systemName: kind.icon).font(.system(size: 72)).foregroundStyle(.white.opacity(0.12))
                    .padding(14).accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(contrast == .increased ? 1 : 0), lineWidth: 2))
        .shadow(color: .black.opacity(contrast == .increased ? 0 : 0.12), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMain ? "Ví chính" : "")
    }

    private var personCard: some View {
        let tint = CategoryStyle.tint(for: "person.crop.circle")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: kind.icon).accessibilityHidden(true)
                Text(wallet.name).fixedSize(horizontal: false, vertical: true)
            }.font(.headline)
            Text(kind.title).font(.caption).foregroundStyle(.secondary)
            if let balance {
                AmountText(amount: balance, style: .system(.title, design: .rounded).bold())
                if balance < 0 { Label("Đang nợ", systemImage: "exclamationmark.circle").font(.caption) }
            } else { Text("Chưa tính được số dư") }
        }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(16)
            .background(LinearGradient(colors: [tint.opacity(contrast == .increased ? 0 : 0.2), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint, lineWidth: contrast == .increased ? 2 : 0.5))
            .accessibilityElement(children: .combine)
    }
}
