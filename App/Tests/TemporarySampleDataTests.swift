import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
#else
@testable import SaveMoney
#endif

@MainActor
final class TemporarySampleDataTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([Wallet.self, Category.self, Transaction.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testSeedsOnlyOnceWithoutTransactions() async throws {
        let container = try container()
        let suite = "SampleDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try TemporarySampleData.installIfNeeded(container: container, defaults: defaults)
        try TemporarySampleData.installIfNeeded(container: container, defaults: defaults)
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Wallet>()), 2)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Category>()), 5)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertTrue(defaults.bool(forKey: TemporarySampleData.marker))
    }

    func testExistingLedgerNeverReceivesSamples() async throws {
        let container = try container()
        let suite = "SampleDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        container.mainContext.insert(Wallet(name: "Đã có"))
        try container.mainContext.save()
        try TemporarySampleData.installIfNeeded(container: container, defaults: defaults)
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Wallet>()), 1)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Category>()), 0)
    }
}
