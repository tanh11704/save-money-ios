import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

final class RecurringPresentationTests: XCTestCase {
    func testPastAnchorPreviewShowsExactImmediateCountAndCursorSuppressesPast() {
        let calendar = LocalCalendar.calendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        var draft = RecurringDraft(); draft.frequency = .daily
        draft.startDate = calendar.date(byAdding: .day, value: -3, to: now)!
        XCTAssertEqual(RecurringPresentation.preview(draft, generatedThrough: nil, now: now).catchUp,
                       "Sẽ tạo ngay 4 giao dịch từ 02/11/2026 đến 05/11/2026.")
        XCTAssertNil(RecurringPresentation.preview(draft, generatedThrough: now, now: now).catchUp)
        XCTAssertTrue(RecurringPresentation.preview(draft, generatedThrough: now, now: now).upcoming.contains("06/11/2026"))
    }
}
