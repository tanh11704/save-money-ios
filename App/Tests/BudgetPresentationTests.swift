import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

final class BudgetPresentationTests: XCTestCase {
    func testWarningUsesEffectiveRulesAndDraftReplacement() {
        let month = ReportingMonth(), category = UUID()
        let rules = [BudgetRule(scope: .total, limit: 100, startMonth: month),
                     BudgetRule(scope: .category(category), limit: 80, startMonth: month)]
        XCTAssertTrue(BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: rules, replacing: .category(category), limit: 101))
        XCTAssertFalse(BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: rules, replacing: .category(category), limit: 100))
        XCTAssertTrue(BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: rules, replacing: .total, limit: 70))
        XCTAssertFalse(BudgetPresentation.categoryLimitsExceedTotal(month: month, rules: [], replacing: .category(category), limit: 100))
    }
    func testRemainingAndVoiceOverIncludeExplicitStatus() throws {
        let progress = try BudgetService.progress(scope: .total, limit: 100, spent: 120)
        XCTAssertEqual(BudgetPresentation.remaining(progress), "Vượt 20 ₫")
        XCTAssertEqual(BudgetPresentation.voiceOver(progress, name: "Tổng"), "Tổng, đã chi 120 đồng trên 100 đồng, Vượt 20 đồng")
    }
    func testCompactRemainingKeepsFullVoiceOverAmount() throws {
        let remaining = try BudgetService.progress(scope: .total, limit: 3_620_000, spent: 1_250_000)
        XCTAssertEqual(BudgetPresentation.remainingCompact(remaining), "Còn 2,37tr")
        XCTAssertEqual(BudgetPresentation.remaining(remaining), "Còn 2.370.000 ₫")
        let over = try BudgetService.progress(scope: .total, limit: 50_000, spent: 100_000)
        XCTAssertEqual(BudgetPresentation.remainingCompact(over), "Vượt 50k")
        let zero = try BudgetService.progress(scope: .total, limit: 100, spent: 100)
        XCTAssertEqual(BudgetPresentation.remainingCompact(zero), "Còn 0 ₫")
    }
    func testTinyLimitAndMaximumSpendingKeepDisplayPercentageCapped() throws {
        let progress = try BudgetService.progress(scope: .total, limit: 1, spent: Int64.max)
        XCTAssertEqual(progress.percentageTenths, 9_999)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.level, .over)
    }

}
