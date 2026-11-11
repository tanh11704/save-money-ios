import AppIntents
import Foundation

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Thêm khoản chi"
    static var description = IntentDescription("Mở SaveMoney để chọn danh mục và lưu khoản chi sau khi mở khóa.")
    static var openAppWhenRun = true
    @Parameter(title: "Số tiền") var amount: Int?
    @MainActor func perform() async throws -> some IntentResult {
        let value = amount.flatMap { (1...MoneyFormatter.maximumInput).contains(Int64($0)) ? Int64($0) : nil }
        AppRouter.shared.enqueue(.add(kind: .expense, amount: value)); return .result()
    }
}
struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Thêm khoản thu"
    static var openAppWhenRun = true
    @Parameter(title: "Số tiền") var amount: Int?
    @MainActor func perform() async throws -> some IntentResult {
        let value = amount.flatMap { (1...MoneyFormatter.maximumInput).contains(Int64($0)) ? Int64($0) : nil }
        AppRouter.shared.enqueue(.add(kind: .income, amount: value)); return .result()
    }
}
struct OpenHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Mở lịch sử SaveMoney"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRouter.shared.enqueue(.history); return .result() }
}
struct OpenStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Mở thống kê SaveMoney"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRouter.shared.enqueue(.stats); return .result() }
}
struct TransferIntent: AppIntent {
    static var title: LocalizedStringResource = "Chuyển tiền giữa các ví"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRouter.shared.enqueue(.transfer(from: nil)); return .result() }
}
struct SaveMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(), phrases: ["Ghi chi tiêu \(.applicationName)", "Thêm khoản chi \(.applicationName)"], shortTitle: "Thêm khoản chi", systemImageName: "minus.circle")
        AppShortcut(intent: AddIncomeIntent(), phrases: ["Thêm khoản thu \(.applicationName)"], shortTitle: "Thêm khoản thu", systemImageName: "plus.circle")
        AppShortcut(intent: OpenHistoryIntent(), phrases: ["Mở lịch sử \(.applicationName)"], shortTitle: "Lịch sử", systemImageName: "list.bullet")
        AppShortcut(intent: TransferIntent(), phrases: ["Chuyển tiền \(.applicationName)"], shortTitle: "Chuyển tiền", systemImageName: "arrow.left.arrow.right")
        AppShortcut(intent: OpenStatsIntent(), phrases: ["Mở thống kê \(.applicationName)"], shortTitle: "Thống kê", systemImageName: "chart.bar")
    }
}
