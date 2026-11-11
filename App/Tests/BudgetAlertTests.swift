import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

@MainActor
final class BudgetAlertTests: XCTestCase {
    private final class Scheduler: NotificationScheduling {
        var authorized = true
        var failing = false
        var alerts: [BudgetAlert] = []
        func isAuthorized() async -> Bool { authorized }
        func schedule(_ alert: BudgetAlert) async throws {
            if failing { throw BackupError.unreadable }
            alerts.append(alert)
        }
    }
    private func progress(_ spent: Int64, scope: BudgetRule.Scope = .total) throws -> [BudgetService.Progress] {
        [try BudgetService.progress(scope: scope, limit: 100, spent: spent)]
    }
    private func setup() -> (BudgetAlertService, Scheduler, UserDefaults, String) {
        let scheduler = Scheduler(), suite = "BudgetAlertTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (BudgetAlertService(scheduler: scheduler, defaults: defaults), scheduler, defaults, suite)
    }
    func testAmountsArePrivateByDefaultAndDetailedOnlyWhenOptedIn() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        await service.notify(month: ReportingMonth(), before: try progress(0), after: try progress(80), categories: [])
        XCTAssertEqual(scheduler.alerts.first?.body, "Đã dùng hơn 80% hạn mức tổng tháng này.")
        XCTAssertFalse(scheduler.alerts[0].body.contains("₫"))
        defaults.set(true, forKey: BudgetAlertService.showsAmountsKey)
        await service.notify(month: ReportingMonth(), before: try progress(80), after: try progress(100), categories: [])
        XCTAssertTrue(scheduler.alerts[1].body.contains("100 / 100 ₫"))
    }

    func testEightyPercentOnlyOnceUntilHundred() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        await service.notify(month: ReportingMonth(), before: try progress(70), after: try progress(80), categories: [])
        await service.notify(month: ReportingMonth(), before: try progress(80), after: try progress(90), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 1)
        XCTAssertTrue(scheduler.alerts[0].id.hasSuffix(".80"))
        await service.notify(month: ReportingMonth(), before: try progress(90), after: try progress(100), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 2)
    }
    func testJumpAcrossBothThresholdsAndDeleteReinsertDoesNotRepeat() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        await service.notify(month: ReportingMonth(), before: try progress(70), after: try progress(120), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 2)
        await service.notify(month: ReportingMonth(), before: try progress(120), after: try progress(70), categories: [])
        await service.notify(month: ReportingMonth(), before: try progress(70), after: try progress(120), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 2)
        let restarted = BudgetAlertService(scheduler: scheduler, defaults: defaults)
        await restarted.notify(month: ReportingMonth(), before: try progress(0), after: try progress(120), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 2)
    }
    func testNewMonthCanAlertAgainAndOldMonthIsSilent() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let november = try ReportingMonth(year: 2026, month: 11), december = try ReportingMonth(year: 2026, month: 12)
        await service.notify(month: november, before: try progress(0), after: try progress(80), categories: [], now: november.interval.start)
        await service.notify(month: december, before: try progress(0), after: try progress(80), categories: [], now: december.interval.start)
        XCTAssertEqual(scheduler.alerts.count, 2)
        XCTAssertNotEqual(scheduler.alerts[0].id, scheduler.alerts[1].id)
        await service.notify(month: november, before: try progress(0), after: try progress(120), categories: [], now: december.interval.start)
        XCTAssertEqual(scheduler.alerts.count, 2)
    }
    func testPermissionDeniedAndFailedSchedulingAreSilentAndDoNotMarkSent() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let month = ReportingMonth()
        let key = BudgetAlertService.key(scope: .total, month: month, threshold: .warning)
        scheduler.authorized = false
        await service.notify(month: month, before: try progress(0), after: try progress(80), categories: [])
        XCTAssertTrue(scheduler.alerts.isEmpty); XCTAssertFalse(defaults.bool(forKey: key))
        scheduler.authorized = true; scheduler.failing = true
        await service.notify(month: month, before: try progress(0), after: try progress(80), categories: [])
        XCTAssertTrue(scheduler.alerts.isEmpty); XCTAssertFalse(defaults.bool(forKey: key))
        scheduler.failing = false
        await service.notify(month: month, before: try progress(0), after: try progress(80), categories: [])
        XCTAssertEqual(scheduler.alerts.count, 1); XCTAssertTrue(defaults.bool(forKey: key))
    }
    func testTotalAndCategoryHaveIndependentKeys() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let category = Category(name: "Ăn uống", kind: .expense)
        let before = try progress(70) + progress(70, scope: .category(category.id))
        let after = try progress(80) + progress(80, scope: .category(category.id))
        await service.notify(month: ReportingMonth(), before: before, after: after, categories: [category])
        XCTAssertEqual(scheduler.alerts.count, 2)
        XCTAssertEqual(Set(scheduler.alerts.map(\.id)).count, 2)
        XCTAssertTrue(scheduler.alerts[1].body.contains("Ăn uống"))
    }
    func testTransfersAndIncomeDoNotChangeProgressOrNotify() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let a = Wallet(name: "A"), b = Wallet(name: "B"), category = Category(name: "Lương", kind: .income)
        let month = ReportingMonth(), rules = [BudgetRule(scope: .total, limit: 100, startMonth: ReportingMonth())]
        let transactions = [Transaction(amount: 120, kind: .transfer, wallet: a, toWallet: b),
                            Transaction(amount: 120, kind: .income, wallet: a, category: category)]
        let before = try BudgetService.progress(month: month, rules: rules, transactions: [])
        let after = try BudgetService.progress(month: month, rules: rules, transactions: transactions)
        await service.notify(month: month, before: before, after: after, categories: [category])
        XCTAssertEqual(before, after); XCTAssertTrue(scheduler.alerts.isEmpty)
    }
    func testConcurrentRequestsDoNotScheduleDuplicates() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let before = try progress(0), after = try progress(120), month = ReportingMonth()
        async let first: Void = service.notify(month: month, before: before, after: after, categories: [])
        async let second: Void = service.notify(month: month, before: before, after: after, categories: [])
        _ = await (first, second)
        XCTAssertEqual(scheduler.alerts.count, 2)
    }
    func testLoweredLimitDoesNotCatchUpThresholdsAlreadyExceededBeforeNextSave() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let month = ReportingMonth()
        // Spending is already above the lowered limit before the next save.
        let before = [try BudgetService.progress(scope: .total, limit: 50, spent: 70)]
        let after = [try BudgetService.progress(scope: .total, limit: 50, spent: 75)]
        await service.notify(month: month, before: before, after: after, categories: [])
        XCTAssertTrue(scheduler.alerts.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: BudgetAlertService.key(scope: .total, month: month, threshold: .warning)))
        XCTAssertFalse(defaults.bool(forKey: BudgetAlertService.key(scope: .total, month: month, threshold: .over)))
    }

    func testAfterLoweringLimitOnlyNewlyCrossedUnsentThresholdCanNotify() async throws {
        let (service, scheduler, defaults, suite) = setup(); defer { defaults.removePersistentDomain(forName: suite) }
        let month = ReportingMonth()
        // Lowering to 80 with 70 spent already passes 80%, but not 100%.
        let before = [try BudgetService.progress(scope: .total, limit: 80, spent: 70)]
        let below = [try BudgetService.progress(scope: .total, limit: 80, spent: 75)]
        let crossed = [try BudgetService.progress(scope: .total, limit: 80, spent: 80)]
        await service.notify(month: month, before: before, after: below, categories: [])
        XCTAssertTrue(scheduler.alerts.isEmpty)
        await service.notify(month: month, before: below, after: crossed, categories: [])
        XCTAssertEqual(scheduler.alerts.map(\.id), [BudgetAlertService.key(scope: .total, month: month, threshold: .over)])
        // A previously sent threshold stays suppressed after another crossing.
        await service.notify(month: month, before: below, after: crossed, categories: [])
        XCTAssertEqual(scheduler.alerts.count, 1)
    }

}
