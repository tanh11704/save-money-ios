#if !SWIFT_PACKAGE
import Foundation
import SwiftData
import XCTest
@testable import SaveMoney

@MainActor
final class TransactionBudgetIntegrationTests: XCTestCase {
    private final class Scheduler: NotificationScheduling {
        var alerts: [BudgetAlert] = []
        var scheduled: (() -> Void)?
        func isAuthorized() async -> Bool { true }
        func schedule(_ alert: BudgetAlert) async throws { alerts.append(alert); scheduled?() }
    }
    private func fixture() throws -> (ModelContainer, TransactionScreenStore, Scheduler, UserDefaults, String) {
        let schema = Schema(versionedSchema: SaveMoneySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let wallet = Wallet(name: "Ví"), category = SaveMoney.Category(name: "Ăn uống", kind: .expense)
        context.insert(wallet); context.insert(category)
        try BudgetPersistence.setLimit(100_000, scope: .total, from: ReportingMonth(), context: context)
        try BudgetPersistence.setLimit(100_000, scope: .category(category.id), from: ReportingMonth(), context: context)
        try context.save()
        let suite = "TransactionBudgetIntegrationTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        let scheduler = Scheduler(), alerts = BudgetAlertService(scheduler: scheduler, defaults: defaults)
        let store = TransactionScreenStore(budgetAlerts: alerts); store.configure(container: container)
        return (container, store, scheduler, defaults, suite)
    }
    func testCalculatorSaveAndEditUpdateLedgerAndBudgetChips() async throws {
        let (_, store, _, defaults, suite) = try fixture(); defer { defaults.removePersistentDomain(forName: suite) }
        var expression = AmountExpression(amount: 120_000)
        expression.apply(.plus)
        for digit in [4, 5, 0, 0, 0] { expression.apply(.digit(digit)) }
        expression.apply(.minus)
        for digit in [1, 5, 0, 0, 0] { expression.apply(.digit(digit)) }
        let wallet = try XCTUnwrap(store.wallets.first), category = try XCTUnwrap(store.categories.first)
        let draft = TransactionDraft(amount: try XCTUnwrap(expression.result), wallet: wallet, category: category)
        try store.save(draft, editing: nil)
        XCTAssertEqual(store.transactions.first?.amount, 150_000)
        XCTAssertEqual(store.budgetSubtitles(on: draft.date)[category.id], "Vượt 50.000 ₫")
        let record = try XCTUnwrap(store.transactions.first)
        expression = AmountExpression(amount: record.amount); expression.apply(.plus)
        for digit in [5, 0, 0, 0, 0] { expression.apply(.digit(digit)) }
        var edit = draft; edit.amount = try XCTUnwrap(expression.result)
        try store.save(edit, editing: record.id)
        XCTAssertEqual(store.transactions.count, 1); XCTAssertEqual(store.transactions[0].amount, 200_000)
    }
    func testSuccessfulSaveSchedulesBothThresholdsForBothScopes() async throws {
        let (_, store, scheduler, defaults, suite) = try fixture(); defer { defaults.removePersistentDomain(forName: suite) }
        let sent = expectation(description: "Four threshold notifications"); sent.expectedFulfillmentCount = 4
        scheduler.scheduled = { sent.fulfill() }
        try store.save(TransactionDraft(amount: 120_000, wallet: store.wallets[0], category: store.categories[0]), editing: nil)
        await fulfillment(of: [sent], timeout: 5)
        XCTAssertEqual(scheduler.alerts.count, 4)
        XCTAssertEqual(store.transactions.count, 1)
    }
    func testRejectedSaveDoesNotScheduleAlerts() async throws {
        let (_, store, scheduler, defaults, suite) = try fixture(); defer { defaults.removePersistentDomain(forName: suite) }
        let sent = expectation(description: "No notification after failed save"); sent.isInverted = true
        scheduler.scheduled = { sent.fulfill() }
        XCTAssertThrowsError(try store.save(TransactionDraft(amount: 0, wallet: store.wallets[0], category: store.categories[0]), editing: nil))
        await fulfillment(of: [sent], timeout: 0.2)
        XCTAssertTrue(scheduler.alerts.isEmpty); XCTAssertTrue(store.transactions.isEmpty)
    }
}
#endif
