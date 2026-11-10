import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

final class MoneyFormatterTests: XCTestCase {
    func testRequiredRoundTrips() {
        let cases: [(Int64, String)] = [(0, "0 ₫"), (999, "999 ₫"), (1_000, "1.000 ₫"), (999_999_999_999, "999.999.999.999 ₫")]
        for (amount, text) in cases {
            XCTAssertEqual(MoneyFormatter.string(from: amount), text)
            XCTAssertEqual(MoneyFormatter.amount(from: text), amount)
            XCTAssertEqual(MoneyFormatter.amount(from: String(amount)), amount)
        }
    }

    func testMalformedAndOutOfRangeInputIsRejected() {
        for text in ["", " ", "1.00", "1..000", ".100", "100.", "01.000", "1000.000", "-1", "−1", "1,000", "1.5", "abc", "１２３", "1 000", "1₫", "1000000000000", "9223372036854775808"] {
            XCTAssertNil(MoneyFormatter.amount(from: text), text)
        }
    }

    func testSignedBalancesAndIntegerLimitsFormatExactly() {
        XCTAssertEqual(MoneyFormatter.string(from: -1_250_000), "−1.250.000 ₫")
        XCTAssertEqual(MoneyFormatter.string(from: Int64.min), "−9.223.372.036.854.775.808 ₫")
        XCTAssertEqual(MoneyFormatter.string(from: Int64.max), "9.223.372.036.854.775.807 ₫")
    }

    func testKeyboardActionsAndCap() {
        var amount: Int64 = 0
        for key in [MoneyFormatter.Key.digit(1), .digit(2), .digit(5), .tripleZero] {
            amount = MoneyFormatter.applying(key, to: amount)
        }
        XCTAssertEqual(amount, 125_000)
        XCTAssertEqual(MoneyFormatter.applying(.backspace, to: amount), 12_500)
        XCTAssertEqual(MoneyFormatter.applying(.digit(9), to: 99_999_999_999), MoneyFormatter.maximumInput)
        XCTAssertEqual(MoneyFormatter.applying(.digit(0), to: MoneyFormatter.maximumInput), MoneyFormatter.maximumInput)
        XCTAssertEqual(MoneyFormatter.applying(.tripleZero, to: 999_999_999), 999_999_999_000)
        XCTAssertEqual(MoneyFormatter.applying(.tripleZero, to: 1_000_000_000), 1_000_000_000)
        XCTAssertEqual(MoneyFormatter.applying(.backspace, to: 0), 0)
        XCTAssertEqual(MoneyFormatter.applying(.backspace, to: 1_000_000_000_000), 100_000_000_000)
        XCTAssertEqual(MoneyFormatter.applying(.tripleZero, to: 0), 0)
        XCTAssertEqual(MoneyFormatter.applying(.digit(10), to: 123), 123)
    }
}
