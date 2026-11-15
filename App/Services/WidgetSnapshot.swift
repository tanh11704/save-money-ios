import Foundation

/// The only data the widget ever sees: a small summary the app writes after each reload.
/// The SwiftData store never moves into the App Group, so a broken or missing group only
/// costs the widget its numbers, never the ledger. Compiled into the app and the widget.
struct WidgetSnapshot: Codable, Equatable {
    static let currentVersion = 1
    var version = currentVersion
    var generatedAt: Date
    /// Local midnight of the day the per-day figures were computed for.
    var day: Date
    /// "tháng 11" or "tháng 11 (25/10–24/11)".
    var cycleName: String
    /// Days left in the cycle, today included.
    var daysLeft: Int
    /// Off by default: the widget then shows only percentages, never amounts.
    var showsAmounts: Bool
    /// Display-only spent/limit of the total budget; nil without a total budget.
    var budgetFraction: Double?
    /// 0 normal, 1 warning (≥ 80%), 2 over.
    var budgetLevel: Int?
    // Amounts are left out entirely unless `showsAmounts` is on.
    var totalBalance: Int64?
    var todayLeft: Int64?
    var perDay: Int64?
    var spentToday: Int64?
    var cycleSpent: Int64?
    var cycleLimit: Int64?

    func isCurrent(now: Date = Date(), calendar: Calendar) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}

/// Locates the App Group shared with the widget. SideStore may rename the group when it
/// re-signs the app, so the real identifier is read from the embedded provisioning profile
/// and the configured one is only a fallback.
enum SharedContainer {
    static let baseGroupID = "group.vn.tanh11704.SaveMoney"
    static let showsAmountsKey = "SaveMoney.widget.showsAmounts"
    static let widgetKinds = ["SaveMoneyWidgetTrial", "SaveMoneyLockQuickAdd"]
    private static let fileName = "widget-snapshot.json"

    static var groupID: String {
        let groups = provisionedGroups(bundle: .main)
        return groups.first { $0.hasPrefix(baseGroupID) } ?? groups.first ?? baseGroupID
    }

    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent(fileName)
    }

    /// False when the build has no App Group (Simulator, unsigned IPA): the widget keeps its quick actions.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot?) -> Bool {
        guard let url = snapshotURL else { return false }
        do {
            if let snapshot {
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch { return false }
    }

    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data), snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// App Group identifiers granted by `embedded.mobileprovision` (a CMS envelope around a plist).
    static func provisionedGroups(bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return [] }
        return groups(fromProvisioningProfile: data)
    }

    static func groups(fromProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}
