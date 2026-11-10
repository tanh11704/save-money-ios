import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import SaveMoneyCore
private typealias LedgerClock = SaveMoneyCore.Clock
#else
@testable import SaveMoney
private typealias LedgerClock = SaveMoney.Clock
#endif

private final class LockTestClock: LedgerClock { var now = Date(timeIntervalSince1970: 1_789_000_000) }
@MainActor
private final class FakeAuthenticator: Authenticator {
    var available = true
    var result = true
    var calls = 0
    var holding = false
    var continuation: CheckedContinuation<Bool, Never>?
    func authenticate(reason: String) async -> Bool {
        calls += 1
        if holding { return await withCheckedContinuation { continuation = $0 } }
        return result
    }
    func cancel() { }
}

@MainActor
final class AppLockTests: XCTestCase {
    @MainActor private final class Fixture {
        let suite = "AppLockTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let auth = FakeAuthenticator()
        let clock = LockTestClock()
        let lock: AppLockService
        init(enabled: Bool = true) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(enabled, forKey: AppLockService.enabledKey)
            lock = AppLockService(authenticator: auth, clock: clock, defaults: defaults)
        }
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }
    func testColdStartIsLockedOnlyWhenEnabled() async {
        let enabled = Fixture(); defer { enabled.clean() }
        XCTAssertEqual(enabled.lock.state, .locked)
        let disabled = Fixture(enabled: false); defer { disabled.clean() }
        XCTAssertEqual(disabled.lock.state, .unlocked)
    }
    func testUnderAndExactlyThirtySecondsStayUnlockedOverThirtyLocks() async {
        let f = Fixture(); defer { f.clean() }
        await f.lock.unlock()
        for duration in [29.0, 30.0] {
            f.lock.enteredBackground(); f.clock.now.addTimeInterval(duration); f.lock.becameActive()
            XCTAssertEqual(f.lock.state, .unlocked)
        }
        f.lock.enteredBackground(); f.clock.now.addTimeInterval(31); f.lock.becameActive()
        XCTAssertEqual(f.lock.state, .locked)
    }
    func testFailureRemainsLockedAndCanRetry() async {
        let f = Fixture(); defer { f.clean() }
        f.auth.result = false; await f.lock.unlock()
        XCTAssertEqual(f.lock.state, .locked); XCTAssertNotNil(f.lock.message)
        f.auth.result = true; await f.lock.unlock()
        XCTAssertEqual(f.lock.state, .unlocked)
    }
    func testInactiveDoesNotRelockOrLoopDuringAuthentication() async {
        let f = Fixture(); defer { f.clean() }
        f.auth.holding = true
        let task = Task { await f.lock.unlock() }
        while f.auth.continuation == nil { await Task.yield() }
        XCTAssertEqual(f.lock.state, .authenticating)
        f.lock.inactive(); f.lock.becameActive()
        await f.lock.unlock()
        XCTAssertEqual(f.auth.calls, 1)
        XCTAssertEqual(f.lock.state, .authenticating)
        f.auth.continuation?.resume(returning: true)
        await task.value
        XCTAssertEqual(f.lock.state, .unlocked)
        f.lock.inactive(); f.lock.becameActive()
        XCTAssertEqual(f.lock.state, .unlocked)
    }
    func testDisabledNeverLocksAfterBackground() async {
        let f = Fixture(enabled: false); defer { f.clean() }
        f.lock.enteredBackground(); f.clock.now.addTimeInterval(100); f.lock.becameActive()
        await f.lock.unlock()
        XCTAssertEqual(f.lock.state, .unlocked); XCTAssertEqual(f.auth.calls, 0)
    }
    func testEnableAndDisableBothRequireSuccessfulAuthentication() async {
        let f = Fixture(enabled: false); defer { f.clean() }
        f.auth.result = false
        let failedEnable = await f.lock.setEnabled(true)
        XCTAssertFalse(failedEnable); XCTAssertFalse(f.lock.enabled)
        f.auth.result = true
        let enabled = await f.lock.setEnabled(true)
        XCTAssertTrue(enabled); XCTAssertTrue(f.lock.enabled)
        f.auth.result = false
        let failedDisable = await f.lock.setEnabled(false)
        XCTAssertFalse(failedDisable); XCTAssertTrue(f.lock.enabled)
        f.auth.result = true
        let disabled = await f.lock.setEnabled(false)
        XCTAssertTrue(disabled); XCTAssertFalse(f.lock.enabled)
        XCTAssertFalse(f.defaults.bool(forKey: AppLockService.enabledKey))
        XCTAssertEqual(f.auth.calls, 4)
    }
    func testNoPasscodeCannotEnable() async {
        let f = Fixture(enabled: false); defer { f.clean() }
        f.auth.available = false
        let result = await f.lock.setEnabled(true)
        XCTAssertFalse(result); XCTAssertFalse(f.lock.enabled); XCTAssertEqual(f.auth.calls, 0)
        XCTAssertNotNil(f.lock.message)
    }
    func testLateAuthenticationCannotUnlockAfterEnteringBackground() async {
        let f = Fixture(); defer { f.clean() }
        f.auth.holding = true
        let task = Task { await f.lock.unlock() }
        while f.auth.continuation == nil { await Task.yield() }
        f.lock.enteredBackground()
        f.auth.continuation?.resume(returning: true)
        await task.value
        XCTAssertEqual(f.lock.state, .locked)
    }
}
