import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class CategoryPaletteTests: XCTestCase {
    func testKnownSymbolsAndStableFallback() {
        XCTAssertEqual(CategoryPalette.index(for: "fork.knife"), 1)
        XCTAssertEqual(CategoryPalette.index(for: "car"), 2)
        XCTAssertEqual(CategoryPalette.index(for: "unknown.future.symbol"), 7)
        for symbol in CategorySymbols.all { XCTAssertTrue((1...10).contains(CategoryPalette.index(for: symbol.name))) }
    }
}
