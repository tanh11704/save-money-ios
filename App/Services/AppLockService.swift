import Combine
import Foundation
import LocalAuthentication

@MainActor
protocol Authenticator {
    var available: Bool { get }
    func authenticate(reason: String) async -> Bool
    func cancel()
}

@MainActor
final class DeviceAuthenticator: Authenticator {
    private var context: LAContext?
    var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        self.context = context
        context.localizedCancelTitle = "Hủy"
        defer { if self.context === context { self.context = nil } }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
    func cancel() { context?.invalidate() }
}

@MainActor
final class AppLockService: ObservableObject {
    enum State: Equatable { case locked, unlocked, authenticating }
    @Published private(set) var state: State
    @Published private(set) var enabled: Bool
    @Published private(set) var message: String?
    static let enabledKey = "SaveMoney.appLockEnabled"
    private let authenticator: any Authenticator
    private let clock: any Clock
    private let defaults: UserDefaults
    private var backgroundDate: Date?
    private var generation = 0

    init(authenticator: any Authenticator, clock: any Clock = SystemClock(), defaults: UserDefaults = .standard) {
        self.authenticator = authenticator; self.clock = clock; self.defaults = defaults
        let initialEnabled = defaults.bool(forKey: Self.enabledKey)
        enabled = initialEnabled
        state = initialEnabled ? .locked : .unlocked
    }
    func inactive() { /* System authentication is inactive, not background. */ }
    func enteredBackground() {
        backgroundDate = clock.now
        if state == .authenticating {
            generation += 1; authenticator.cancel()
            state = enabled ? .locked : .unlocked
        }
    }
    func becameActive() {
        defer { backgroundDate = nil }
        guard enabled else { state = .unlocked; return }
        if let backgroundDate, clock.now.timeIntervalSince(backgroundDate) > 30 { state = .locked }
    }
    func unlock() async {
        guard enabled, state == .locked else { return }
        guard authenticator.available else { message = "Không thể xác thực. Hãy kiểm tra mật mã máy trong Cài đặt iPhone."; return }
        generation += 1; let token = generation
        state = .authenticating; message = nil
        let success = await authenticator.authenticate(reason: "Mở khóa SaveMoney")
        guard token == generation else { return }
        state = success ? .unlocked : .locked
        if !success { message = "Chưa xác thực được. Hãy thử lại bằng Face ID hoặc mật mã máy." }
    }
    @discardableResult func setEnabled(_ value: Bool) async -> Bool {
        guard value != enabled else { return true }
        guard state != .authenticating else { return false }
        guard authenticator.available else { message = "Cần đặt mật mã máy trước khi bật khóa ứng dụng."; return false }
        let previous = state
        generation += 1; let token = generation
        state = .authenticating; message = nil
        let success = await authenticator.authenticate(reason: value ? "Bật khóa SaveMoney" : "Tắt khóa SaveMoney")
        guard token == generation else { return false }
        guard success else { state = previous; message = "Thay đổi chưa được xác thực."; return false }
        enabled = value; defaults.set(value, forKey: Self.enabledKey); state = .unlocked
        return true
    }
}
