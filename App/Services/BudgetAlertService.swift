import Foundation
import UserNotifications

struct BudgetAlert: Equatable {
    let id: String
    let body: String
}

@MainActor
protocol NotificationScheduling {
    func isAuthorized() async -> Bool
    func schedule(_ alert: BudgetAlert) async throws
}

@MainActor
struct SystemBudgetNotificationScheduler: NotificationScheduling {
    func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func schedule(_ alert: BudgetAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Ngân sách SaveMoney"; content.body = alert.body; content.sound = .default
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}

@MainActor
final class BudgetAlertService {
    let scheduler: any NotificationScheduling
    let defaults: UserDefaults
    private var inFlight = Set<String>()
    init(scheduler: (any NotificationScheduling)? = nil, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler ?? SystemBudgetNotificationScheduler(); self.defaults = defaults
    }

    // Inputs are immutable snapshots taken before and after a successful save.
    // Older months remain visible in reports, but do not send stale alerts.
    func notify(month: ReportingMonth, before: [BudgetService.Progress], after: [BudgetService.Progress],
                categories: [Category], now: Date = Date()) async {
        guard month == ReportingMonth(containing: now), await scheduler.isAuthorized() else { return }
        for progress in after {
            let previous = before.first { $0.scope == progress.scope }?.spent ?? 0
            guard let thresholds = try? BudgetService.crossedThresholds(limit: progress.limit, before: previous, after: progress.spent) else { continue }
            for threshold in thresholds {
                let key = Self.key(scope: progress.scope, month: month, threshold: threshold)
                guard !defaults.bool(forKey: key), inFlight.insert(key).inserted else { continue }
                defer { inFlight.remove(key) }
                let name = BudgetPresentation.name(for: progress.scope, categories: categories)
                let amounts = BudgetPresentation.usage(progress)
                let body = threshold == .warning
                    ? "\(name) đã dùng 80% hạn mức tháng \(month.month) (\(amounts))"
                    : "Đã vượt \(name.lowercased()) tháng \(month.month): \(amounts)"
                do {
                    try await scheduler.schedule(BudgetAlert(id: key, body: body))
                    defaults.set(true, forKey: key)
                } catch { /* Notifications never turn a committed save into a failure. */ }
            }
        }
    }
    static func key(scope: BudgetRule.Scope, month: ReportingMonth, threshold: BudgetService.Threshold) -> String {
        let scopeID: String
        switch scope { case .total: scopeID = "total"; case .category(let id): scopeID = id.uuidString }
        return "budget.alert.\(scopeID).\(String(format: "%04d%02d", month.year, month.month)).\(threshold.rawValue)"
    }
}
