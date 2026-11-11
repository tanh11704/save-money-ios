import SwiftData
import SwiftUI

@MainActor
struct AppShell: View {
    @StateObject private var runtime: AppRuntime
    @Environment(\.scenePhase) private var scenePhase

    init(container: ModelContainer) { _runtime = StateObject(wrappedValue: AppRuntime(container: container)) }
    var body: some View {
        ProtectedAppView(runtime: runtime, lock: runtime.lock)
            .onOpenURL { if let route = AppRoute.parse($0) { runtime.router.enqueue(route) } }
            .overlay {
                if scenePhase != .active {
                    PrivacyScreen().accessibilityAddTraits(.isModal)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: runtime.enteredBackground()
                case .active: runtime.becameActive()
                case .inactive: runtime.lock.inactive()
                @unknown default: break
                }
            }
    }
}

@MainActor
private struct ProtectedAppView: View {
    let runtime: AppRuntime
    @ObservedObject var lock: AppLockService
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if lock.state == .unlocked {
                ContentView(settings: runtime.settings, lock: lock)
                    .accessibilityHidden(phase != .active)
            } else {
                LockScreen(lock: lock)
            }
        }
        .environmentObject(runtime)
        .environmentObject(runtime.router)
        .onChange(of: lock.state, initial: true) { _, state in
            if state == .unlocked && phase == .active { runtime.generateRecurring() }
        }
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .environment(\.calendar, LocalCalendar.calendar)
        .environment(\.timeZone, LocalCalendar.calendar.timeZone)
    }
}

private struct PrivacyScreen: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            Label("SaveMoney", systemImage: "lock.fill").font(.title)
        }
    }
}

@MainActor
struct LockScreen: View {
    @ObservedObject var lock: AppLockService
    @Environment(\.scenePhase) private var phase
    @State private var automaticallyRequested = false
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").accessibilityHidden(true)
                Text("SaveMoney đã khóa").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.font(.title).accessibilityElement(children: .combine)
            if lock.state == .authenticating { ProgressView("Đang xác thực…") }
            else {
                Button { Task { await lock.unlock() } } label: {
                    Text("Mở khóa").frame(minWidth: 100, minHeight: 44)
                }.buttonStyle(.borderedProminent)
            }
            if let message = lock.message { Text(message).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .task { requestAutomaticUnlock() }
        .onChange(of: phase) { _, _ in requestAutomaticUnlock() }
    }
    private func requestAutomaticUnlock() {
        guard phase == .active, !automaticallyRequested else { return }
        automaticallyRequested = true
        Task { await lock.unlock() }
    }
}
