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
        XCTAssertEqual(transactions.map { labels[$0.id]?.csvKind }, ["Cho vay", "Thu nợ", "Đi vay", "Trả nợ", "Trả hộ", "Cho vay"])
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
        XCTAssertEqual(file.schemaVersion, 5)
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
        XCTAssertTrue(String(decoding: csv, as: UTF8.self).contains("Trả hộ"))
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

@MainActor
final class BalanceAdjustmentTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SaveMoneySchemaV3.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func fetch(_ container: ModelContainer) throws -> (wallets: [Wallet], transactions: [Transaction]) {
        let context = ModelContext(container)
        return (try context.fetch(FetchDescriptor<Wallet>()), try context.fetch(FetchDescriptor<Transaction>()))
    }

    func testDifferenceRules() throws {
        XCTAssertEqual(try BalanceAdjustmentService.difference(current: 5_400_000, actual: 5_450_000), 50_000)
        XCTAssertEqual(try BalanceAdjustmentService.difference(current: 100, actual: -200), -300)
        XCTAssertThrowsError(try BalanceAdjustmentService.difference(current: 7, actual: 7)) {
            XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .alreadyMatches)
        }
        XCTAssertThrowsError(try BalanceAdjustmentService.difference(current: 0, actual: MoneyFormatter.maximumInput + 1)) {
            XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .outOfRange)
        }
        XCTAssertThrowsError(try BalanceAdjustmentService.difference(current: Int64.min, actual: Int64.max)) {
            XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .outOfRange)
        }
    }

    func testAdjustmentSetsRealBalanceWithoutTouchingStatsOrNetWorthTotals() throws {
        let container = try makeContainer()
        let bank = Wallet(name: "Tài khoản", openingBalance: 5_000_000, kind: .bank)
        let cash = Wallet(name: "Tiền mặt", openingBalance: 100_000)
        let food = Category(name: "Ăn uống", kind: .expense)
        container.mainContext.insert(bank); container.mainContext.insert(cash); container.mainContext.insert(food)
        container.mainContext.insert(Transaction(amount: 30_000, kind: .expense, wallet: bank, category: food))
        try container.mainContext.save()
        let before = try fetch(container)
        let statsBefore = try StatsService.report(month: ReportingMonth(), transactions: before.transactions)

        let service = BalanceAdjustmentService(container: container)
        try service.adjust(walletID: bank.id, to: 5_020_000)          // +50.000
        try service.adjust(walletID: cash.id, to: 80_000, note: "Lẻ") // −20.000

        let after = try fetch(container)
        let adjustmentWallets = after.wallets.filter(\.isAdjustment)
        XCTAssertEqual(adjustmentWallets.count, 1, "the hidden wallet is created once and reused")
        XCTAssertEqual(adjustmentWallets.first?.openingBalance, 0)
        let balances = try BalanceCalculator.balances(wallets: after.wallets, transactions: after.transactions, allowMissingCategory: true)
        XCTAssertEqual(balances[bank.id], 5_020_000)
        XCTAssertEqual(balances[cash.id], 80_000)

        let adjustments = after.transactions.filter(TransactionPresentation.isAdjustment)
        XCTAssertEqual(adjustments.count, 2)
        XCTAssertTrue(adjustments.allSatisfy { $0.kindRaw == TransactionKind.transfer.rawValue && $0.category == nil })
        XCTAssertEqual(adjustments.map(TransactionPresentation.amount).sorted(), ["+50.000 ₫", "−20.000 ₫"].sorted())

        let statsAfter = try StatsService.report(month: ReportingMonth(), transactions: after.transactions)
        XCTAssertEqual(statsAfter.expense, statsBefore.expense)
        XCTAssertEqual(statsAfter.income, statsBefore.income)

        let worth = try NetWorth.make(wallets: after.wallets, transactions: after.transactions)
        XCTAssertEqual(worth.ownWallets, 5_100_000)
        XCTAssertEqual(worth.receivable, 0)
        XCTAssertEqual(worth.payable, 0)
        // Invariant: own wallets + adjustment wallet == every wallet's balance.
        let all = try BalanceCalculator.totalBalance(wallets: after.wallets, transactions: after.transactions, allowMissingCategory: true)
        XCTAssertEqual(worth.ownWallets + (balances[adjustmentWallets[0].id] ?? 0), all)
    }

    func testRejectsPeopleArchivedWalletsAndMatchingBalance() throws {
        let container = try makeContainer()
        let cash = Wallet(name: "Tiền mặt", openingBalance: 1_000)
        let lan = Wallet(name: "Lan", kind: .person)
        let old = Wallet(name: "Cũ", openingBalance: 5); old.isArchived = true
        [cash, lan, old].forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        let service = BalanceAdjustmentService(container: container)
        XCTAssertThrowsError(try service.adjust(walletID: lan.id, to: 10)) { XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .notOwnWallet) }
        XCTAssertThrowsError(try service.adjust(walletID: old.id, to: 10)) { XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .notOwnWallet) }
        XCTAssertThrowsError(try service.adjust(walletID: cash.id, to: 1_000)) { XCTAssertEqual($0 as? BalanceAdjustmentService.AdjustmentError, .alreadyMatches) }
        XCTAssertTrue(try fetch(container).transactions.isEmpty, "failed adjustments leave no data")
        XCTAssertFalse(try fetch(container).wallets.contains(where: \.isAdjustment))
    }

    func testValidatorOnlyAllowsTransfersBetweenAdjustmentAndOwnWallets() {
        let cash = Wallet(name: "Tiền mặt"), lan = Wallet(name: "Lan", kind: .person)
        let system = Wallet(name: BalanceAdjustmentService.walletName, kind: .adjustment)
        let food = Category(name: "Ăn uống", kind: .expense)
        XCTAssertTrue(TransactionValidator.validationErrors(TransactionDraft(amount: 1, kind: .transfer, wallet: system, toWallet: cash)).isEmpty)
        XCTAssertTrue(TransactionValidator.validationErrors(TransactionDraft(amount: 1, kind: .transfer, wallet: cash, toWallet: system)).isEmpty)
        XCTAssertTrue(TransactionValidator.validationErrors(TransactionDraft(amount: 1, kind: .expense, wallet: system, category: food)).contains(.adjustmentMisuse))
        XCTAssertTrue(TransactionValidator.validationErrors(TransactionDraft(amount: 1, kind: .transfer, wallet: system, toWallet: lan)).contains(.adjustmentMisuse))
        XCTAssertFalse(system.isOwn)
        XCTAssertFalse(lan.isOwn)
        XCTAssertTrue(cash.isOwn)
    }

    func testAdjustmentWalletCannotBeEditedOrArchivedAndBackupIsV5() throws {
        let container = try makeContainer()
        let cash = Wallet(name: "Tiền mặt", openingBalance: 1_000), bank = Wallet(name: "Bank", openingBalance: 0, kind: .bank)
        container.mainContext.insert(cash); container.mainContext.insert(bank)
        try container.mainContext.save()
        try BalanceAdjustmentService(container: container).adjust(walletID: cash.id, to: 1_500)
        let system = try XCTUnwrap(try fetch(container).wallets.first(where: \.isAdjustment))
        let wallets = WalletService(container: container)
        XCTAssertThrowsError(try wallets.archive(id: system.id)) { XCTAssertEqual($0 as? ManagementError, .invalidKind) }
        XCTAssertThrowsError(try wallets.update(id: system.id, with: WalletDraft(name: "X", kind: .cash))) { XCTAssertEqual($0 as? ManagementError, .invalidKind) }
        XCTAssertThrowsError(try WalletService.validate(WalletDraft(name: "Y", kind: .adjustment), wallets: [])) { XCTAssertEqual($0 as? ManagementError, .invalidKind) }

        let exporter = BackupExporter(container: container, directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let file = try exporter.capture()
        XCTAssertEqual(file.schemaVersion, 5)
        let validated = try BackupValidator.validate(file)
        XCTAssertEqual(validated.totalBalance, 1_500, "restore summary counts only own wallets")
        var downgraded = file; downgraded.schemaVersion = 4
        XCTAssertThrowsError(try BackupValidator.validate(downgraded))
    }
}
