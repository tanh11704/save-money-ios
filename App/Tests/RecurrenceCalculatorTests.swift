import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

final class RecurrenceCalculatorTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { LocalCalendar.calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    func testMonthlyAnchorDoesNotDriftAndLeapFebruary() {
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: date(2026, 1, 31), frequency: .monthly, interval: 1, end: nil, after: nil, through: date(2026, 4, 30)), [date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: date(2028, 1, 31), frequency: .monthly, interval: 1, end: nil, after: nil, through: date(2028, 2, 29)).last, date(2028, 2, 29))
    }
    func testYearlyLeapDayAndBiweeklyAcrossYears() {
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: date(2028, 2, 29), frequency: .yearly, interval: 1, end: nil, after: date(2028, 2, 29), through: date(2032, 2, 29)), [date(2029, 2, 28), date(2030, 2, 28), date(2031, 2, 28), date(2032, 2, 29)])
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: date(2026, 12, 25), frequency: .weekly, interval: 2, end: nil, after: nil, through: date(2027, 1, 22)), [date(2026, 12, 25), date(2027, 1, 8), date(2027, 1, 22)])
    }
    func testCursorExclusiveUpperAndEndInclusiveAndInvalidInput() {
        let start = date(2026, 1, 1)
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: start, frequency: .daily, interval: 1, end: date(2026, 1, 3), after: start, through: date(2026, 1, 5)), [date(2026, 1, 2), date(2026, 1, 3)])
        XCTAssertTrue(RecurrenceCalculator.occurrences(start: start, frequency: .daily, interval: 0, end: nil, after: nil, through: start).isEmpty)
        XCTAssertTrue(RecurrenceCalculator.occurrences(start: start, frequency: .daily, interval: 1, end: date(2025, 12, 31), after: nil, through: start).isEmpty)
        XCTAssertEqual(RecurrenceCalculator.occurrences(start: start, frequency: .daily, interval: 1, end: nil, after: nil, through: date(2030, 1, 1)).count, 400)
    }
    func testTimezoneIndependentKeysAndOldCursorJump() {
        let original = NSTimeZone.default; defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 1, 31), id = UUID()
        let result = RecurrenceCalculator.occurrences(start: start, frequency: .monthly, interval: 1, end: nil, after: date(2030, 1, 31), through: date(2030, 3, 31))
        XCTAssertEqual(result, [date(2030, 2, 28), date(2030, 3, 31)])
        XCTAssertEqual(RecurrenceCalculator.key(ruleID: id, occurrence: start), id.uuidString + ".20260131")
    }
}
