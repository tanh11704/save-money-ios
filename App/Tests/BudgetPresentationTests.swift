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
}
