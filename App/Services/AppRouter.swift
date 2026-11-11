import Combine
import Foundation

enum AppRoute: Equatable {
    case add(kind: TransactionKind?, amount: Int64?)
    case history, stats
    static func parse(_ url: URL) -> AppRoute? {
        guard url.scheme?.lowercased() == "savemoney", url.path.isEmpty || url.path == "/",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch url.host?.lowercased() {
        case "history": return .history
        case "stats": return .stats
        case "add":
            let items = components.queryItems ?? []
            guard items.filter({ $0.name == "kind" }).count <= 1, items.filter({ $0.name == "amount" }).count <= 1 else { return nil }
            let kind = items.first { $0.name == "kind" }?.value.flatMap(TransactionKind.init(rawValue:))
            let amount = items.first { $0.name == "amount" }?.value.flatMap(MoneyFormatter.amount(from:)).flatMap { $0 > 0 ? $0 : nil }
            return .add(kind: kind, amount: amount)
        default: return nil
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    struct Request: Identifiable { let id = UUID(); let route: AppRoute }
    static let shared = AppRouter()
    @Published private(set) var pending: Request?
    func enqueue(_ route: AppRoute) { pending = Request(route: route) }
    func take(unlocked: Bool) -> AppRoute? {
        guard unlocked else { return nil }
        defer { pending = nil }
        return pending?.route
    }
}
