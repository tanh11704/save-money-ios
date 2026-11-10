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
final class DefaultDataSeederTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([Wallet.self, Category.self, Transaction.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testExactDefaultsOnceEvenAfterArchivingEverything() async throws {
        let container = try container()
        let suite = "DefaultSeedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try DefaultDataSeeder.installIfNeeded(container: container, defaults: defaults)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        XCTAssertEqual(wallets.count, 1)
        XCTAssertEqual(wallets.first?.name, "Tiền mặt")
        XCTAssertEqual(wallets.first?.openingBalance, 0)
        XCTAssertEqual(wallets.first?.kindRaw, "cash")
        XCTAssertEqual(Set(categories.filter { $0.kindRaw == "expense" }.map(\.name)), Set(["Ăn uống", "Đi lại", "Nhà ở", "Hóa đơn", "Mua sắm", "Sức khỏe", "Giải trí", "Khác"]))
        XCTAssertEqual(Set(categories.filter { $0.kindRaw == "income" }.map(\.name)), Set(["Lương", "Thu nhập khác"]))
        let originalIDs = Set(categories.map(\.id))
        XCTAssertTrue(defaults.bool(forKey: "didSeedDefaults"))
        // Simulate legacy/direct store archive; WalletService itself forbids the last wallet.
        wallets.forEach { $0.isArchived = true }
        categories.forEach { $0.isArchived = true }
        try context.save()
        try DefaultDataSeeder.installIfNeeded(container: container, defaults: defaults)
        try DefaultDataSeeder.installIfNeeded(container: container, defaults: defaults)
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Wallet>()), 1)
        XCTAssertEqual(Set(try reader.fetch(FetchDescriptor<Category>()).map(\.id)), originalIDs)
        XCTAssertTrue(try reader.fetch(FetchDescriptor<Category>()).allSatisfy(\.isArchived))
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    func testFlagPreventsSeedingAnEmptyStore() async throws {
        let container = try container()
        let suite = "DefaultSeedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: DefaultDataSeeder.marker)
        try DefaultDataSeeder.installIfNeeded(container: container, defaults: defaults)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Wallet>()), 0)
    }

    func testNeitherPartiallyPopulatedStoreIsSeeded() async throws {
        for existingWallet in [true, false] {
            let container = try container()
            let suite = "DefaultSeedTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if existingWallet { container.mainContext.insert(Wallet(name: "Đã có")) }
            else { container.mainContext.insert(Category(name: "Đã có", kind: .expense)) }
            try container.mainContext.save()
            try DefaultDataSeeder.installIfNeeded(container: container, defaults: defaults)
            let reader = ModelContext(container)
            XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Wallet>()), existingWallet ? 1 : 0)
            XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Category>()), existingWallet ? 0 : 1)
        }
    }
}
