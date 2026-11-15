import SwiftUI

// MARK: - Shared pieces

/// Gradient palette for wallet cards. Index stored by `WalletAppearance`; nil picks one by wallet kind.
enum WalletPalette {
    static let names = ["Lá", "Ngọc", "Biển", "Chàm", "Tím", "Hồng", "Cam", "Than"]
    static let gradients: [[Color]] = [
        [Color(red: 0.16, green: 0.66, blue: 0.42), Color(red: 0.05, green: 0.45, blue: 0.33)],
        [Color(red: 0.10, green: 0.63, blue: 0.66), Color(red: 0.03, green: 0.42, blue: 0.50)],
        [Color(red: 0.22, green: 0.52, blue: 0.96), Color(red: 0.10, green: 0.33, blue: 0.78)],
        [Color(red: 0.36, green: 0.36, blue: 0.90), Color(red: 0.22, green: 0.20, blue: 0.66)],
        [Color(red: 0.62, green: 0.36, blue: 0.92), Color(red: 0.42, green: 0.20, blue: 0.72)],
        [Color(red: 0.93, green: 0.36, blue: 0.56), Color(red: 0.74, green: 0.18, blue: 0.40)],
        [Color(red: 0.98, green: 0.56, blue: 0.22), Color(red: 0.86, green: 0.36, blue: 0.10)],
        [Color(red: 0.36, green: 0.40, blue: 0.46), Color(red: 0.20, green: 0.23, blue: 0.28)]
    ]

    static func index(for wallet: Wallet) -> Int {
        if let chosen = WalletAppearance.colorIndex(for: wallet.id) { return chosen }
        switch WalletKind(rawValue: wallet.kindRaw) ?? .other {
        case .cash: return 0
        case .bank: return 2
        case .card: return 4
        default: return 7
        }
    }

    static func gradient(for wallet: Wallet) -> LinearGradient { gradient(index: index(for: wallet)) }
    static func gradient(index: Int) -> LinearGradient {
        LinearGradient(colors: gradients[max(0, min(gradients.count - 1, index))], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension AppearanceSettings.Accent {
    var color: Color? {
        switch self {
        case .standard: return nil
        case .teal: return Color(red: 0.07, green: 0.60, blue: 0.62)
        case .blue: return Color(red: 0.16, green: 0.45, blue: 0.93)
        case .indigo: return Color(red: 0.33, green: 0.32, blue: 0.86)
        case .pink: return Color(red: 0.89, green: 0.30, blue: 0.52)
        case .orange: return Color(red: 0.95, green: 0.48, blue: 0.13)
        }
    }
}

/// Budget bar with a marker where an even pace would be today.
struct PaceBar: View {
    let pace: BudgetPace
    var onDark = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var fill: Color {
        if pace.spentFraction >= 1 { return Color("Expense") }
        switch pace.status {
        case .ahead: return .orange
        case .onTrack, .behind: return onDark ? .white : Color("Income")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill((onDark ? Color.white : Color.secondary).opacity(0.25))
                    Capsule().fill(fill).frame(width: max(6, proxy.size.width * min(1, pace.spentFraction)))
                    // Today's even-pace marker.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(onDark ? Color.white : Color.primary)
                        .frame(width: 2, height: 16)
                        .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * pace.elapsedFraction - 1)))
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack {
                Text(pace.text).font(.caption.weight(.semibold))
                    .foregroundStyle(onDark ? Color.white : pace.status == .ahead ? Color.orange : Color.secondary)
                Spacer(minLength: 4)
                Text("\(MoneyFormatter.compact(pace.spent)) / \(MoneyFormatter.compact(pace.limit))").font(.caption).monospacedDigit()
                    .foregroundStyle(onDark ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đã chi \(Int((pace.spentFraction * 100).rounded())) phần trăm hạn mức, đã qua \(pace.elapsedDays) trên \(pace.dayCount) ngày. \(pace.text)")
    }
}

struct StreakBadge: View {
    let days: Int
    let loggedToday: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: days > 0 ? "flame.fill" : "pencil.and.list.clipboard")
                .foregroundStyle(days > 0 ? Color.orange : Color.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(days > 0 ? "\(days) ngày ghi chép liên tục" : "Bắt đầu chuỗi ghi chép").font(.subheadline.weight(.semibold))
                Text(loggedToday ? "Hôm nay đã ghi, tuyệt!" : days > 0 ? "Ghi một khoản hôm nay để giữ chuỗi" : "Ghi mỗi ngày một khoản để tạo thói quen")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact coloured wallet tile for horizontal strips.
struct MiniWalletCard: View {
    let wallet: Wallet
    let balance: Int64?
    let isMain: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: (WalletKind(rawValue: wallet.kindRaw) ?? .other).icon).accessibilityHidden(true)
                Spacer(minLength: 0)
                if isMain { Image(systemName: "star.fill").font(.caption).accessibilityHidden(true) }
            }
            Text(wallet.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(balance.map(MoneyFormatter.compact) ?? "—").font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 140, height: 96, alignment: .leading)
        .background(WalletPalette.gradient(for: wallet), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wallet.name)\(isMain ? ", ví chính" : ""), \(balance.map { MoneyFormatter.string(from: $0).replacingOccurrences(of: "₫", with: "đồng") } ?? "chưa tính được số dư")")
    }
}

// MARK: - Overview

@MainActor
struct OverviewView: View {
    @ObservedObject var store: TransactionScreenStore
    @ObservedObject var settings: BackupScreenStore
    let lock: AppLockService
    @Binding var showingSettings: Bool
    let onAdd: (TransactionKind) -> Void
    let onShowHistory: () -> Void
    let onShowStats: () -> Void
    @State private var showingTransfer = false
    @State private var editing: Transaction?
    @State private var selectedWallet: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearanceSettings.accentKey) private var accentRaw = AppearanceSettings.Accent.standard.rawValue

    private func weekdayName(_ date: Date) -> String {
        ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][LocalCalendar.calendar.component(.weekday, from: date) - 1]
    }

    private var greeting: String {
        let hour = LocalCalendar.calendar.component(.hour, from: Date())
        return hour < 11 ? "Chào buổi sáng" : hour < 14 ? "Chào buổi trưa" : hour < 18 ? "Chào buổi chiều" : "Chào buổi tối"
    }

    var body: some View {
        let month = ReportingMonth()
        let allowance = store.flexibleAllowance()
        let total = store.progress(in: month).first { $0.scope == .total }
        let pace = total.flatMap { BudgetPace.make(spent: $0.spent, limit: $0.limit, month: month) }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(weekdayName(Date())), \(TransactionPresentation.shortDate(Date()))")
                        .font(.title2.bold())
                }
                hero(allowance: allowance, pace: pace, month: month)
                quickActions
                Card { StreakBadge(days: store.loggingStreak, loggedToday: LoggingStreak.hasLoggedToday(transactions: store.transactions)) }
                walletStrip
                upcomingSection
                recentSection
            }
            .padding()
        }
        .appScreenBackground()
        .navigationTitle("Tổng quan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44)
                        .overlay(alignment: .topTrailing) {
                            if settings.health.level == .critical { Circle().fill(.red).frame(width: 9, height: 9).offset(x: -6, y: 8) }
                        }
                }
                .accessibilityLabel(settings.health.level == .critical ? "Cài đặt, sao lưu cần kiểm tra" : "Cài đặt")
            }
        }
        .navigationDestination(isPresented: $showingSettings) { SettingsView(store: settings, lock: lock) }
        .navigationDestination(item: $selectedWallet) { id in
            if let wallet = store.wallets.first(where: { $0.id == id }) { WalletDetailView(store: store, wallet: wallet) }
        }
        .sheet(isPresented: $showingTransfer) { NavigationStack { TransferSheet(store: store) } }
        .sheet(item: $editing) { transaction in NavigationStack { TransactionFormView(store: store, original: transaction) } }
        .refreshable { try? store.reload() }
    }

    // MARK: Hero

    @ViewBuilder private func hero(allowance: StatsService.FlexibleAllowance?, pace: BudgetPace?, month: ReportingMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(month.title).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                Spacer()
                if let allowance { Text("Còn \(allowance.daysLeft) ngày").font(.caption.weight(.semibold)).opacity(0.9) }
            }
            if let allowance {
                VStack(alignment: .leading, spacing: 2) {
                    Text(allowance.leftToday >= 0 ? "Hôm nay còn được tiêu" : "Hôm nay đã vượt").font(.subheadline).opacity(0.9)
                    Text(MoneyFormatter.string(from: abs(allowance.leftToday)))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("≈ \(MoneyFormatter.compact(allowance.perDay))/ngày · hôm nay đã chi \(MoneyFormatter.compact(allowance.spentToday))")
                        .font(.caption).opacity(0.9)
                }
                .accessibilityElement(children: .combine)
                if let pace { PaceBar(pace: pace, onDark: true) }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tổng số dư").font(.subheadline).opacity(0.9)
                    Text(store.totalBalance).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
                .accessibilityElement(children: .combine)
                NavigationLink { BudgetListView(store: store) } label: {
                    Label("Đặt hạn mức tổng để biết mỗi ngày được tiêu bao nhiêu", systemImage: "target")
                        .font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(reduceMotion ? nil : .snappy, value: allowance?.leftToday)
    }

    private var heroBackground: LinearGradient {
        let accent = AppearanceSettings.Accent(rawValue: accentRaw) ?? .standard
        let base = accent.color ?? Color(red: 0.08, green: 0.55, blue: 0.45)
        return LinearGradient(colors: [base, base.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Sections

    private var quickActions: some View {
        HStack(spacing: Spacing.s) {
            action("Chi", icon: "minus", tint: Color("Expense")) { onAdd(.expense) }
            action("Thu", icon: "plus", tint: Color("Income")) { onAdd(.income) }
            action("Chuyển", icon: "arrow.left.arrow.right", tint: Color("Transfer")) { showingTransfer = true }
            action("Thống kê", icon: "chart.bar.fill", tint: .purple, perform: onShowStats)
        }
    }

    private func action(_ title: String, icon: String, tint: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(tint, in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var walletStrip: some View {
        let wallets = store.wallets.filter { $0.isOwn && !$0.isArchived }
        if !wallets.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Ví").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(wallets, id: \.id) { wallet in
                            Button { selectedWallet = wallet.id } label: {
                                MiniWalletCard(wallet: wallet, balance: store.balanceValues[wallet.id], isMain: wallet.id == store.mainWalletID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Xem chi tiết ví")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder private var upcomingSection: some View {
        let items = store.upcoming()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Sắp tới · 7 ngày").font(.headline)
                Card {
                    VStack(spacing: Spacing.s) {
                        ForEach(items) { item in
                            HStack(spacing: 12) {
                                CalendarTile(date: item.date)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(item.kind == .cardDue ? "Hạn thanh toán thẻ" : item.kind == .installment ? "Trả góp" : "Định kỳ")
                                        .font(.caption).foregroundStyle(item.kind == .cardDue ? Color("Expense") : .secondary)
                                }
                                Spacer(minLength: 4)
                                if let amount = item.amount { Text(MoneyFormatter.compact(amount)).font(.subheadline).monospacedDigit() }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(TransactionPresentation.shortDate(item.date))
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var recentSection: some View {
        let recent = Array(store.transactions.prefix(5))
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Gần đây").font(.headline)
                Spacer()
                if !recent.isEmpty { Button("Xem tất cả", action: onShowHistory).font(.subheadline).frame(minHeight: 44) }
            }
            if recent.isEmpty {
                EmptyState(image: "illus-empty-history", title: "Chưa có giao dịch", message: "Bắt đầu ghi chi tiêu", actionTitle: "Ghi khoản đầu tiên") { onAdd(.expense) }
            } else {
                Card {
                    VStack(spacing: 4) {
                        ForEach(recent, id: \.id) { transaction in
                            Button { editing = transaction } label: { TransactionRow(transaction: transaction, debt: store.debtLabels[transaction.id]) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Chạm hai lần để sửa giao dịch")
                            if transaction.id != recent.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}
