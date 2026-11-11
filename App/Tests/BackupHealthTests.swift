import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif
final class BackupHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func health(backupAge: Int = 0, copyAge: Int = 0, integrityAge: Int = 0, healthy: Bool = true,
                        count: Int = 0, changes: Int = 0, noBackup: Bool = false, noCopy: Bool = false, error: String? = nil) -> BackupHealth {
        func ago(_ days: Int) -> Date { LocalCalendar.calendar.date(byAdding: .day, value: -days, to: now)! }
        return BackupHealth.evaluate(now: now, lastBackup: noBackup ? nil : ago(backupAge), fileCount: noBackup ? 0 : 1,
            lastExternalCopy: noCopy ? nil : ago(copyAge), lastIntegrityCheck: .init(date: ago(integrityAge), healthy: healthy),
            changesSinceBackup: changes, lastError: error, transactionCount: count)
    }
    func testEveryBoundaryAndCriticalReason() {
        XCTAssertEqual(health(backupAge: 7).level, .good); XCTAssertEqual(health(backupAge: 8).level, .attention)
        XCTAssertEqual(health(backupAge: 14).level, .attention); XCTAssertEqual(health(backupAge: 15).level, .critical)
        XCTAssertEqual(health(copyAge: 14).level, .good); XCTAssertEqual(health(copyAge: 15).level, .attention)
        XCTAssertEqual(health(integrityAge: 30).level, .good); XCTAssertEqual(health(integrityAge: 31).level, .attention)
        XCTAssertEqual(health(changes: 20).level, .good); XCTAssertEqual(health(changes: 21).level, .attention)
        XCTAssertEqual(health(count: 50, noCopy: true).level, .good); XCTAssertEqual(health(count: 51, noCopy: true).level, .critical)
        XCTAssertEqual(health(noBackup: true).level, .critical); XCTAssertEqual(health(error: "failed").level, .critical)
        XCTAssertEqual(health(healthy: false).level, .critical)
    }
}
