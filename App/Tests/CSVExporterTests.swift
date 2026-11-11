import XCTest
import Foundation
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif
final class CSVExporterTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        LocalCalendar.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }
    private func parse(_ data: Data) -> [[String]] {
        var result: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(String(decoding: data.dropFirst(3), as: UTF8.self)); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i+1] == "\"" { cell.append(c); i += 1 } else { quoted.toggle() }
            } else if !quoted && c == "," { row.append(cell); cell = "" }
            else if !quoted && c == "\r\n" { row.append(cell); result.append(row); row = []; cell = "" }
            else { cell.append(c) }
            i += 1
        }
        return result
    }
    func testBOMQuotesInjectionLargeMoneyAndArchivedNames() throws {
        let wallet = Wallet(name: "=Ví"), category = Category(name: "@Ăn uống", kind: .expense)
        wallet.isArchived = true; category.isArchived = true
        let t = Transaction(amount: 999_999_999_999, kind: .expense, date: date(15, 14, 5), note: "món, \"ngon\"\r\nxuống dòng", wallet: wallet, category: category)
        t.recurrenceKey = "key"
        let data = try CSVExporter.csv(transactions: [t], from: date(1), to: date(30))
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let rows = parse(data); XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][8], t.note); XCTAssertEqual(rows[1][6], "'=Ví"); XCTAssertEqual(rows[1][5], "'@Ăn uống")
        XCTAssertEqual(rows[1][3], "999999999999"); XCTAssertEqual(rows[1][4], "-999999999999"); XCTAssertEqual(rows[1][9], "Có")
        t.note = "=SUM(A1)"
        XCTAssertEqual(parse(try CSVExporter.csv(transactions: [t], from: date(1), to: date(30)))[1][8], "'=SUM(A1)")
    }
    func testInclusiveLastDayTransferAndEmptyRange() throws {
        let a = Wallet(name: "A"), b = Wallet(name: "B")
        let included = Transaction(amount: 100, kind: .transfer, date: date(30, 23, 59, 59), wallet: a, toWallet: b)
        let excluded = Transaction(amount: 200, kind: .transfer, date: date(31), wallet: a, toWallet: b)
        let rows = parse(try CSVExporter.csv(transactions: [excluded, included], from: date(1), to: date(30)))
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows[1][4], "0"); XCTAssertEqual(rows[1][5], ""); XCTAssertEqual(rows[1][7], "B")
        XCTAssertEqual(parse(try CSVExporter.csv(transactions: [], from: date(1), to: date(30))).count, 1)
        XCTAssertThrowsError(try CSVExporter.csv(transactions: [], from: date(30), to: date(1)))
    }
}
