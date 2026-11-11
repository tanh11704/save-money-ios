import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias Category = SaveMoneyCore.Category
#else
@testable import SaveMoney
private typealias Category = SaveMoney.Category
#endif

@MainActor
final class IntegrityCheckerTests: XCTestCase {
    func testCleanReadOnlyAndIndependentBalanceWithTransfers() async throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext, a = Wallet(name: "A", openingBalance: 1_000), b = Wallet(name: "B", openingBalance: 2_000)
        let category = Category(name: "Chi", kind: .expense)
        context.insert(a); context.insert(b); context.insert(category)
        context.insert(Transaction(amount: 200, kind: .transfer, wallet: a, toWallet: b))
        context.insert(Transaction(amount: 100, kind: .expense, wallet: b, category: category)); try context.save()
        let report = try IntegrityChecker.check(container: container, backupDirectory: nil)
        XCTAssertTrue(report.isHealthy); XCTAssertTrue(report.issues.isEmpty); XCTAssertEqual(report.totalBalance, 2_900)
        XCTAssertFalse(context.hasChanges)
    }
    func testEveryStructuralIssueAndMissingCategoryWarning() throws {
        let a = Wallet(name: "A"), expense = Category(name: "Chi", kind: .expense), income = Category(name: "Thu", kind: .income)
        func kinds(_ t: Transaction, wallets: [Wallet]? = nil) throws -> [IntegrityIssue] {
            try IntegrityChecker.inspect(wallets: wallets ?? [a], categories: [expense, income], transactions: [t], budgets: [], recurring: []).issues
        }
        let t = Transaction(amount: 1, kind: .expense, wallet: a, category: expense)
        t.wallet = nil; XCTAssertTrue(try kinds(t).contains { $0.kind == .transactionMissingWallet(t.id) })
        t.wallet = a; t.category = nil
        XCTAssertTrue(try kinds(t).contains { $0.kind == .transactionMissingCategory(t.id) && $0.severity == .warning })
        t.category = income; XCTAssertTrue(try kinds(t).contains { $0.kind == .categoryKindMismatch(t.id) })
        t.amount = 0; XCTAssertTrue(try kinds(t).contains { $0.kind == .nonPositiveAmount(t.id) })
        t.amount = 1; t.kindRaw = "transfer"; t.toWallet = nil
        XCTAssertTrue(try kinds(t).contains { $0.kind == .transferMissingDestination(t.id) })
        t.toWallet = a; XCTAssertTrue(try kinds(t).contains { $0.kind == .transferSameWallet(t.id) })
        XCTAssertTrue(try kinds(t).contains { $0.kind == .transferHasCategory(t.id) })
        let b = Wallet(name: "B"); b.id = a.id
        let report = try IntegrityChecker.inspect(wallets: [a, b], categories: [], transactions: [], budgets: [Budget()], recurring: [RecurringRule()])
        XCTAssertTrue(report.issues.contains { $0.kind == .duplicateID(a.id.uuidString) })
        XCTAssertTrue(report.issues.contains { if case .invalidBudget = $0.kind { return true }; return false })
        XCTAssertTrue(report.issues.contains { if case .invalidRecurringRule = $0.kind { return true }; return false })
    }
    func testDuplicateRecurrenceKeyAndOverflow() throws {
        let a = Wallet(name: "A", openingBalance: Int64.max), category = Category(name: "Thu", kind: .income)
        let one = Transaction(amount: 1, kind: .income, wallet: a, category: category), two = Transaction(amount: 1, kind: .income, wallet: a, category: category)
        one.recurrenceKey = "same"; two.recurrenceKey = "same"
        let report = try IntegrityChecker.inspect(wallets: [a], categories: [category], transactions: [one, two], budgets: [], recurring: [])
        XCTAssertTrue(report.issues.contains { $0.kind == .duplicateRecurrenceKey("same") })
        XCTAssertTrue(report.issues.contains { $0.kind == .balanceOverflow }); XCTAssertNil(report.totalBalance)
    }
    func testBackupVersionsChecksumAndMalformedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        for version in 1...3 {
            let url = try XCTUnwrap(bundle.url(forResource: "golden-v\(version)", withExtension: "json", subdirectory: "Fixtures"))
            try Data(contentsOf: url).write(to: folder.appendingPathComponent("v\(version).json"))
        }
        var file = try BackupValidator.read(Data(contentsOf: folder.appendingPathComponent("v1.json"))).file
        file.payload.wallets[0].name += "x"
        try BackupFile.encoder().encode(file).write(to: folder.appendingPathComponent("tampered.json"))
        try Data("bad".utf8).write(to: folder.appendingPathComponent("bad.json"))
        let result = try IntegrityChecker.checkFiles(in: folder)
        XCTAssertEqual(result.checked, 3); XCTAssertEqual(result.issues.count, 2)
        XCTAssertTrue(result.issues.contains { $0.kind == .backupChecksumMismatch("tampered.json") })
        XCTAssertTrue(result.issues.contains { $0.kind == .backupUnreadable("bad.json") })
    }
}
