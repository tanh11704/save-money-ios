#if !SWIFT_PACKAGE
import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import SaveMoney

@MainActor
final class AccessibilityRenderingTests: XCTestCase {
    func testDeveloperReadmeIsNotBundled() {
        XCTAssertNil(Bundle.main.url(forResource: "README", withExtension: "md"))
    }
    func testU8AuditAcrossThreeConfigurations() async throws {
        let configurations: [(DynamicTypeSize, CGSize, String)] = [
            (.large, CGSize(width: 375, height: 667), "SE"),
            (.large, CGSize(width: 402, height: 874), "reference-phone"),
            (.accessibility5, CGSize(width: 375, height: 667), "AX5-SE")
        ]
        for (type, size, name) in configurations {
            for scheme in [ColorScheme.light, .dark] {
                try await render(type: type, scheme: scheme, size: size,
                                 suffix: "U8-" + name + (scheme == .light ? "-light" : "-dark"))
            }
        }
    }
    func testButtonTextAndCategorySymbolsMeetContrastInBothAppearances() throws {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            func linear(_ component: CGFloat) -> Double {
                let value = Double(component)
                if value <= 0.04045 { return value / 12.92 }
                return pow((value + 0.055) / 1.055, 2.4)
            }
            return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let foreground = luminance(try XCTUnwrap(UIColor(named: "OnAccent", in: .main, compatibleWith: traits)))
            for name in ["AccentColor", "Income", "Expense", "Transfer"] {
                let background = luminance(try XCTUnwrap(UIColor(named: name, in: .main, compatibleWith: traits)))
                XCTAssertGreaterThanOrEqual((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05), 4.5, name)
            }
            for index in 1...10 {
                let background = luminance(try XCTUnwrap(UIColor(named: "CategoryTint\(index)", in: .main, compatibleWith: traits)))
                XCTAssertGreaterThanOrEqual(1.05 / (background + 0.05), 4.5)
            }
        }
    }
    func testSemanticAssetColorsAreOpaqueInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for name in ["AccentColor", "Income", "Expense", "Transfer"] {
                let color = try XCTUnwrap(UIColor(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: style)))
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                XCTAssertGreaterThan(alpha, 0.99, name)
                XCTAssertGreaterThan(max(red, green, blue), 0.4, name)
            }
        }
    }
    func testRenderUpdatedMainScreensForReview() async throws {
        for (type, scheme, size, suffix) in [(DynamicTypeSize.accessibility5, ColorScheme.dark, CGSize(width: 375, height: 667), "AX5-dark-small"), (.xSmall, .light, CGSize(width: 430, height: 932), "smallest-light-large")] {
            try await render(type: type, scheme: scheme, size: size, suffix: suffix, includeNames: ["add", "history", "stats", "wallets", "transfer", "wallet-detail", "debts", "debt-person", "debt-payment", "settings", "encryption", "restore", "lock", "restore-success", "recurring"])
        }
    }
    func testRenderScreensAtAX5DarkForVisualReview() async throws {
        try await render(type: .accessibility5, scheme: .dark, size: CGSize(width: 375, height: 667), suffix: "AX5-dark-small")
    }
    func testRenderScreensAtSmallestLightForVisualReview() async throws {
        try await render(type: .xSmall, scheme: .light, size: CGSize(width: 430, height: 932), suffix: "smallest-light-large")
    }
    func testRenderWalletAndAxisAtAX5AfterLayoutFixes() async throws {
        try await render(type: .accessibility5, scheme: .dark, size: CGSize(width: 375, height: 667), suffix: "AX5-dark-small", includeNames: ["wallet-form", "daily-chart"])
    }
    private func render(type: DynamicTypeSize, scheme: ColorScheme, size: CGSize, suffix: String, includeNames: Set<String>? = nil) async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext, wallet = Wallet(name: "Tiền mặt và sinh hoạt", openingBalance: 5_000_000)
        let category = SaveMoney.Category(name: "Ăn uống và sinh hoạt gia đình", kind: .expense, icon: "fork.knife")
        context.insert(wallet); context.insert(category)
        let bank = Wallet(name: "Tài khoản", openingBalance: 3_000_000, kind: .bank)
        let person = Wallet(name: "Lan", kind: .person)
        context.insert(bank); context.insert(person)
        context.insert(Transaction(amount: 500_000, kind: .transfer, date: Date().addingTimeInterval(-172800), wallet: wallet, toWallet: person))
        let transaction = Transaction(amount: 1_250_000, kind: .expense, note: "Ghi chú dài để kiểm tra khả năng xuống dòng", wallet: wallet, category: category)
        context.insert(transaction)
        let recurring = RecurringRule(); recurring.name = "Tiền nhà và sinh hoạt hằng tháng"; recurring.amount = 500_000; recurring.wallet = wallet; recurring.category = category
        context.insert(recurring)
        try BudgetPersistence.setLimit(3_620_000, scope: .category(category.id), from: ReportingMonth(), context: context)
        try context.save()
        let suite = "Render.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var exporter = BackupExporter(container: container, directory: folder); exporter.protection = BackupProtection(defaults: defaults, keyStore: MemoryBackupKeys())
        _ = try exporter.export(kind: .manual)
        let lock = AppLockService(authenticator: DeviceAuthenticator(), defaults: defaults)
        let runtime = AppRuntime(container: container, scheduler: BackupScheduler(exporter: exporter, defaults: defaults), lock: lock)
        let store = TransactionScreenStore(); store.configure(container: container)
        let file = try exporter.capture(), data = try BackupFile.encoder().encode(file)
        let pending = BackupScreenStore.PendingRestore(data: data, summary: try BackupValidator.read(data))
        let report = try StatsService.report(month: ReportingMonth(), transactions: [transaction])
        let daily = try StatsService.dailyExpenses(month: ReportingMonth(), transactions: [transaction])
        let screens: [(String, AnyView)] = [
            ("add", AnyView(TransactionFormView(store: store))),
            ("add-empty", AnyView(TransactionFormView(store: TransactionScreenStore()))),
            ("add-selected", AnyView(TransactionFormView(store: store, prefillWallet: wallet, prefillAmount: 50_000))),
            ("guide", AnyView(GuideView())), ("history", AnyView(TransactionHistoryView(store: store))),
            ("edit", AnyView(TransactionFormView(store: store, original: transaction))), ("wallets", AnyView(WalletListView(store: store))),
            ("wallet-form", AnyView(WalletFormView(store: store, original: wallet))), ("categories", AnyView(CategoryListView(store: store))),
            ("budgets", AnyView(BudgetListView(store: store))), ("budget-form", AnyView(BudgetFormView(store: store, scope: .category(category.id), month: ReportingMonth()))),
            ("recurring", AnyView(RecurringListView(store: store))), ("recurring-form", AnyView(RecurringFormView(store: store, original: recurring))),
            ("debts", AnyView(DebtListView(store: store))), ("debt-person", AnyView(DebtPersonView(store: store, person: person))),
            ("debt-payment", AnyView(TransferSheet(store: store, mode: .debt(person: person, action: .collect), amount: 600_000))),
            ("transfer", AnyView(TransferSheet(store: store, source: wallet, amount: 150_000))), ("wallet-detail", AnyView(WalletDetailView(store: store, wallet: wallet))),
            ("stats", AnyView(StatsView(store: store))), ("category-detail", AnyView(StatsCategoryDetailView(month: ReportingMonth(), key: .init(kind: .expense, categoryID: category.id)))),
            ("daily-chart", AnyView(ScrollView { StatsDailyChart(days: daily, allowance: 66_666).padding() })),
            ("category-chart", AnyView(ScrollView { StatsCategoryChart(slices: StatsService.expenseSlices(report), total: report.expense).padding() })),
            ("category-form", AnyView(CategoryFormView(store: store, original: category))),
            ("integrity", AnyView(IntegrityView(store: runtime.settings))),
            ("restore-success", AnyView(RestoreSuccessView(transactionCount: 2, done: {}))),
            ("settings", AnyView(SettingsView(store: runtime.settings, lock: lock))), ("restore", AnyView(RestoreSummaryView(candidate: pending, store: runtime.settings))),
            ("encryption", AnyView(BackupEncryptionView(store: runtime.settings))), ("csv", AnyView(CSVExportView())), ("lock", AnyView(LockScreen(lock: lock)))
        ]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("SaveMoneyAccessibilityReview")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, content) in screens.filter({ includeNames?.contains($0.0) ?? true }) {
            let view = NavigationStack { content }.modelContainer(container).environmentObject(runtime).environmentObject(runtime.router)
                .environment(\.dynamicTypeSize, type).environment(\.locale, Locale(identifier: "vi_VN"))
                .environment(\.calendar, LocalCalendar.calendar).environment(\.timeZone, LocalCalendar.calendar.timeZone).preferredColorScheme(scheme)
            let host = UIHostingController(rootView: view)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name + "-" + suffix; attachment.lifetime = .keepAlways; add(attachment)
            try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name + "-" + suffix + ".png"))
            window.isHidden = true
        }
    }
}
#endif
