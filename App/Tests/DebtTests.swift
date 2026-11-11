import XCTest
import SwiftData
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class DebtTests: XCTestCase {
    func testGoldenV4AndAllOlderGoldenVersionsRemainReadable() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        for version in 1...4 {
            let url = try XCTUnwrap(bundle.url(forResource: "golden-v\(version)", withExtension: "json", subdirectory: "Fixtures"))
            let file = try BackupValidator.read(Data(contentsOf: url)).file
            XCTAssertEqual(file.schemaVersion, version)
            XCTAssertEqual(file.payload.wallets.filter { $0.kind == "person" }.count, version == 4 ? 1 : 0)
        }
    }
    func testEqualDatesUseIDOrderForDebtLabels() throws {
        let cash = Wallet(name: "Cash"), person = Wallet(name: "Lan", kind: .person)
        let date = Date()
        let lend = Transaction(amount: 100, kind: .transfer, date: date, wallet: cash, toWallet: person)
        let collect = Transaction(amount: 150, kind: .transfer, date: date, wallet: person, toWallet: cash)
        lend.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        collect.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        XCTAssertEqual(try DebtPresentation.labels(transactions: [collect, lend]), try DebtPresentation.labels(transactions: [lend, collect]))
        XCTAssertEqual(try DebtPresentation.labels(transactions: [collect, lend])[collect.id]?.title, "Lan trả nợ")
    }
    private func scenario() -> ([Wallet], [Transaction]) {
        let cash = Wallet(name: "Cash", openingBalance: 2_000_000), bank = Wallet(name: "Bank", openingBalance: 1_000_000)
        let lan = Wallet(name: "Lan", kind: .person), nam = Wallet(name: "Nam", kind: .person)
        let category = Category(name: "Ăn uống", kind: .expense, icon: "fork.knife")
        let start = ReportingMonth().interval.start
        let transactions = [
            Transaction(amount: 500_000, kind: .transfer, date: start, wallet: cash, toWallet: lan),
            Transaction(amount: 200_000, kind: .transfer, date: start.addingTimeInterval(1), wallet: lan, toWallet: bank),
            Transaction(amount: 1_000_000, kind: .transfer, date: start.addingTimeInterval(2), wallet: nam, toWallet: bank),
            Transaction(amount: 400_000, kind: .transfer, date: start.addingTimeInterval(3), wallet: cash, toWallet: nam),
            Transaction(amount: 150_000, kind: .expense, date: start.addingTimeInterval(4), wallet: lan, category: category),
            Transaction(amount: 80_000, kind: .transfer, date: start.addingTimeInterval(5), wallet: cash, toWallet: lan)
        ]
        return ([cash, bank, lan, nam], transactions)
    }
    func testDebtScenariosNetWorthAndExpenseStatistics() throws {
        let (wallets, transactions) = scenario(), lan = wallets[2], nam = wallets[3]
        XCTAssertEqual(try BalanceCalculator.balance(for: lan, transactions: transactions), 230_000)
        XCTAssertEqual(try BalanceCalculator.balance(for: nam, transactions: transactions), -600_000)
        let worth = try NetWorth.make(wallets: wallets, transactions: transactions)
        XCTAssertEqual(worth.ownWallets, 3_220_000)
        XCTAssertEqual(worth.receivable, 230_000); XCTAssertEqual(worth.payable, 600_000)
        XCTAssertEqual(worth.net, 2_850_000)
        XCTAssertEqual(worth.net, try BalanceCalculator.totalBalance(wallets: wallets, transactions: transactions))
        let report = try StatsService.report(month: ReportingMonth(), transactions: transactions)
        XCTAssertEqual(report.income, 0); XCTAssertEqual(report.expense, 150_000)
        let progress = try BudgetService.progress(month: ReportingMonth(), rules: [BudgetRule(scope: .total, limit: 200_000, startMonth: ReportingMonth())], transactions: transactions)
        XCTAssertEqual(progress.first?.spent, 150_000)
    }
    func testLabelsAndCrossingZeroUseBalanceBeforeTransaction() throws {
        let (wallets, transactions) = scenario()
        let labels = try DebtPresentation.labels(transactions: transactions)
        XCTAssertEqual(transactions.map { labels[$0.id]?.title }, ["Cho Lan vay", "Lan trả nợ", "Vay Nam", "Trả nợ Nam", "Lan trả hộ · Ăn uống", "Cho Lan vay"])
        let overpayment = Transaction(amount: 400_000, kind: .transfer, date: transactions.last!.date.addingTimeInterval(1), wallet: wallets[2], toWallet: wallets[0])
        let label = try XCTUnwrap(DebtPresentation.labels(transactions: transactions + [overpayment])[overpayment.id])
        XCTAssertEqual(label.title, "Lan trả nợ"); XCTAssertEqual(label.balanceAfter, -170_000)
        XCTAssertTrue(label.detail?.contains("170.000") == true)
    }
    func testValidationAndOverflow() throws {
        let cash = Wallet(name: "Lan"), person = Wallet(name: "Lan", kind: .person), other = Wallet(name: "Nam", kind: .person)
        XCTAssertNoThrow(try WalletService.validate(WalletDraft(name: "Lan", kind: .person), wallets: [cash]))
        XCTAssertThrowsError(try WalletService.validate(WalletDraft(name: "Lan", kind: .person), wallets: [person]))
        XCTAssertThrowsError(try WalletService.validate(WalletDraft(name: "New", kind: .person, openingBalance: 1), wallets: []))
        XCTAssertThrowsError(try TransactionValidator.validate(TransactionDraft(amount: 1, kind: .transfer, wallet: person, toWallet: other))) { XCTAssertEqual($0 as? TransactionValidator.ValidationError, .personToPerson) }
        let category = Category(name: "Salary", kind: .income, icon: "banknote")
        XCTAssertThrowsError(try TransactionValidator.validate(TransactionDraft(amount: 1, kind: .income, wallet: person, category: category))) { XCTAssertEqual($0 as? TransactionValidator.ValidationError, .incomeToPerson) }
        XCTAssertThrowsError(try NetWorth.make(wallets: [Wallet(name: "Huge", openingBalance: .max), Wallet(name: "Overflow", openingBalance: 1)], transactions: []))
        XCTAssertThrowsError(try NetWorth.make(wallets: [Wallet(name: "Bad legacy", openingBalance: .min, kind: .person)], transactions: []))
    }
    func testBackupV4RoundTripAndOldVersionsRejectPerson() throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let (wallets, transactions) = scenario()
        for wallet in wallets { container.mainContext.insert(wallet) }
        for transaction in transactions { container.mainContext.insert(transaction) }
        try container.mainContext.save()
        let exporter = BackupExporter(container: container, directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let file = try exporter.capture()
        XCTAssertEqual(file.schemaVersion, 4)
        XCTAssertNoThrow(try BackupValidator.validate(file))
        let graph = try BackupValidator.graph(file.payload)
        XCTAssertEqual(try NetWorth.make(wallets: graph.wallets, transactions: graph.transactions), try NetWorth.make(wallets: wallets, transactions: transactions))
        var old = file; old.schemaVersion = 3
        XCTAssertThrowsError(try BackupValidator.validate(old))
        let restoredContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let restoredExporter = BackupExporter(container: restoredContainer, directory: folder)
        _ = try BackupRestorer(container: restoredContainer, exporter: restoredExporter).restore(BackupFile.encoder().encode(file))
        let restoredWallets = try restoredContainer.mainContext.fetch(FetchDescriptor<Wallet>())
        let restoredTransactions = try restoredContainer.mainContext.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(try NetWorth.make(wallets: restoredWallets, transactions: restoredTransactions), try NetWorth.make(wallets: wallets, transactions: transactions))
        let csv = try CSVExporter.csv(transactions: transactions, from: transactions.first!.date, to: transactions.last!.date)
        XCTAssertTrue(String(decoding: csv, as: UTF8.self).contains("Lan trả hộ"))
    }
    func testLastOwnWalletAndOutstandingPersonCannotArchive() throws {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let cash = Wallet(name: "Cash", openingBalance: 1_000), person = Wallet(name: "Lan", kind: .person)
        container.mainContext.insert(cash); container.mainContext.insert(person)
        container.mainContext.insert(Transaction(amount: 100, kind: .transfer, wallet: cash, toWallet: person))
        try container.mainContext.save()
        let service = WalletService(container: container)
        XCTAssertThrowsError(try service.archive(id: cash.id)) { XCTAssertEqual($0 as? ManagementError, .lastActiveWallet) }
        XCTAssertThrowsError(try service.archive(id: person.id)) { XCTAssertEqual($0 as? ManagementError, .personOutstanding) }
    }
}
