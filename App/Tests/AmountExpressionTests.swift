import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

final class AmountExpressionTests: XCTestCase {
    private func enter(_ number: Int64, into expression: inout AmountExpression) {
        for digit in String(number) { expression.apply(.digit(Int(String(digit))!)) }
    }
    func testOrdinaryInputMatchesFormatter() {
        var expression = AmountExpression()
        var amount: Int64 = 0
        for key in [MoneyFormatter.Key.digit(5), .digit(0), .tripleZero, .backspace, .digit(7), .tripleZero] {
            expression.apply(key); amount = MoneyFormatter.applying(key, to: amount)
            XCTAssertEqual(expression.result, amount); XCTAssertFalse(expression.hasOperator)
        }
    }
    func testSumDifferenceAndDisplay() {
        var expression = AmountExpression(amount: 50_000)
        expression.apply(.plus); enter(35_000, into: &expression)
        expression.apply(.minus); enter(5_000, into: &expression)
        XCTAssertEqual(expression.result, 80_000)
        XCTAssertEqual(expression.displayText, "50.000 + 35.000 − 5.000")
        expression.apply(.equals)
        XCTAssertEqual(expression, AmountExpression(amount: 80_000))
    }
    func testOperatorReplacementAndPendingSave() {
        var expression = AmountExpression(amount: 50_000)
        expression.apply(.plus); expression.apply(.minus)
        XCTAssertEqual(expression.result, 50_000)
        enter(5_000, into: &expression)
        XCTAssertEqual(expression.result, 45_000)
        XCTAssertEqual(expression.displayText, "50.000 − 5.000")
    }
    func testBackspaceRestoresPreviousOperand() {
        var expression = AmountExpression(amount: 123)
        expression.apply(.minus); expression.apply(.digit(4))
        expression.apply(.backspace); XCTAssertEqual(expression.current, 0)
        expression.apply(.backspace); XCTAssertEqual(expression.current, 123)
        XCTAssertFalse(expression.hasOperator)
        expression.apply(.backspace); XCTAssertEqual(expression.current, 12)
    }
    func testNegativeEqualsIgnoredAndClear() {
        var expression = AmountExpression(amount: 5_000)
        expression.apply(.minus); enter(8_000, into: &expression)
        XCTAssertEqual(expression.result, -3_000)
        let previous = expression; expression.apply(.equals); XCTAssertEqual(expression, previous)
        expression.apply(.clear); XCTAssertEqual(expression, AmountExpression())
    }
    func testOperandCapAndResultAboveCap() {
        var expression = AmountExpression(amount: MoneyFormatter.maximumInput)
        expression.apply(.digit(9)); XCTAssertEqual(expression.result, MoneyFormatter.maximumInput)
        expression.apply(.plus); enter(MoneyFormatter.maximumInput, into: &expression)
        XCTAssertEqual(expression.result, 1_999_999_999_998)
        expression.apply(.digit(0)); XCTAssertEqual(expression.current, MoneyFormatter.maximumInput)
    }
    func testEditAndOverflowIgnored() {
        var expression = AmountExpression(amount: 200_000)
        expression.apply(.backspace); XCTAssertEqual(expression.result, 20_000)
        expression = AmountExpression(amount: Int64.max)
        expression.apply(.plus)
        let previous = expression; expression.apply(.digit(1)); XCTAssertEqual(expression, previous)
    }
}
