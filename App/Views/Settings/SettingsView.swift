import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct SettingsView: View {
    @ObservedObject var store: BackupScreenStore
    @ObservedObject var lock: AppLockService
    @State private var importing = false
    @State private var sharing: ShareItem?
    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        List {
            Section { backupStatus }
            Section("Sao lưu") {
                if let error = store.error ?? store.scheduler.lastError { Text(error).foregroundStyle(.red) }
                if let message = store.message { Text(message).foregroundStyle(.secondary) }
                Button { store.backupNow() } label: { IconRow(icon: "externaldrive", title: "Sao lưu ngay") }
                Button {
                    if let latest = store.latest { sharing = ShareItem(url: latest) }
                } label: { IconRow(icon: "square.and.arrow.up", title: "Chia sẻ bản mới nhất") }
                    .disabled(store.latest == nil)
                NavigationLink { backupList } label: { IconRow(icon: "doc.on.doc", title: "Danh sách bản sao lưu") }
                Button { importing = true } label: { IconRow(icon: "arrow.counterclockwise", tint: .orange, title: "Khôi phục từ file") }
                HStack { IconRow(icon: "icloud", title: "Sao lưu iCloud của iPhone"); InfoButton(text: "1. Mở Cài đặt → tên bạn → iCloud.\n2. Bật Sao lưu iCloud.\n3. Chia sẻ file backup sang iCloud Drive và giữ thêm một bản ngoài iPhone.") }
                Text(store.scheduler.exporter.protection.enabled ? "Mọi bản sao lưu mới đều được mã hóa, kể cả trước khôi phục." : "Backup mới chưa mã hóa và có thể đọc từ ứng dụng Tệp dù app đang khóa.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Dữ liệu") {
                NavigationLink { CSVExportView() } label: { IconRow(icon: "tablecells", tint: .green, title: "Xuất CSV") }
                if store.scheduler.defaults.object(forKey: "SaveMoney.lastIntegrityCheck") != nil && !store.scheduler.defaults.bool(forKey: "SaveMoney.lastIntegrityHealthy") {
                    Label("Kiểm tra gần nhất có lỗi. Hãy xem kết quả và sao lưu trước khi sửa.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                NavigationLink { IntegrityView(store: store) } label: { IconRow(icon: "checkmark.shield", tint: .green, title: "Kiểm tra toàn vẹn") }
            }
            Section("Bảo mật") {
                NavigationLink { BackupEncryptionView(store: store) } label: { IconRow(icon: "lock.shield", tint: .purple, title: "Mã hóa bản sao lưu") }
                Toggle("Khóa bằng Face ID", isOn: Binding(get: { lock.enabled }, set: { value in Task { _ = await lock.setEnabled(value) } }))
                    .frame(minHeight: 44).disabled(lock.state == .authenticating)
                Text("Khóa sau 30 giây ở nền")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message = lock.message { Text(message).foregroundStyle(.red) }
            }
            Section("Phím tắt") {
                IconRow(icon: "square.stack.3d.up", tint: .purple, title: "Mở nhanh SaveMoney")
                InfoButton(text: "Trong ứng dụng Phím tắt, tìm SaveMoney để mở Thêm chi, Thêm thu, Lịch sử hoặc Thống kê. Phím tắt luôn mở app và yêu cầu mở khóa trước khi nhập dữ liệu.")
            }
            Section("Thông tin") {
                IconRow(icon: "info.circle", tint: .secondary, title: "Phiên bản", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Cài đặt")
        .onAppear { store.refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): store.prepare(url: url)
            case .failure: store.error = "Không mở được file đã chọn."
            }
        }
        .sheet(item: $sharing) { item in
            BackupShareSheet(url: item.url) { completed in if completed { store.sharedSuccessfully() } }
        }
        .sheet(item: $store.passwordRequest, onDismiss: { store.finishPreparedRestore() }) { request in
            BackupPasswordView(store: store, request: request)
        }
        .sheet(item: $store.pending) { pending in
            NavigationStack {
                RestoreSummaryView(candidate: pending, store: store)
            }
        }
    }

    private var backupStatus: some View {
        let health = store.health
        return Card { VStack(alignment: .leading, spacing: 8) {
            Illustration(name: health.level == .good ? "illus-backup-good" : health.level == .attention ? "illus-backup-attention" : "illus-backup-critical")
            Label(health.title, systemImage: health.level == .good ? "checkmark.shield" : "exclamationmark.triangle.fill").font(.headline)
            ForEach(health.reasons, id: \.self) { Label($0, systemImage: "circle.fill").font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            if let date = health.lastBackup { Text("Backup gần nhất: " + TransactionPresentation.shortDate(date)) }
            Text("\(health.fileCount) bản, \(ByteCountFormatter.string(fromByteCount: health.totalBytes, countStyle: .file))")
            if let kind = health.lastBackupKind { Text("Loại gần nhất: " + (kind == .auto ? "Tự động" : kind == .manual ? "Thủ công" : "Trước khôi phục")) }
            if let age = store.scheduler.externalCopyAge { Text("Bản chép ra ngoài gần nhất: \(age) ngày trước") }
            Button("Sao lưu ngay") { store.backupNow() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
        } }
        .foregroundStyle(health.level == .critical ? Color.red : health.level == .attention ? Color.orange : Color.primary)
        .accessibilityElement(children: .combine)
    }

    private var backupList: some View {
        List {
            backupSection("Tự động và thủ công (giữ 10 bản)", entries: store.entries)
            backupSection("Trước khôi phục (giữ 5 bản riêng)", entries: store.preRestore)
        }.navigationTitle("Bản sao lưu")
    }
    private func backupSection(_ title: String, entries: [BackupCatalog.Entry]) -> some View {
        Section(title) {
            if entries.isEmpty { Text("Chưa có bản sao lưu.").foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                Button { store.prepare(url: entry.url) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.url.lastPathComponent).font(.caption).fixedSize(horizontal: false, vertical: true)
                        if entry.encrypted { Label("Đã mã hóa", systemImage: "lock.fill") }
                        if let file = entry.file {
                            BackupCounts(file: file)
                        } else { Text("Cần mật khẩu để xem dữ liệu.").foregroundStyle(.secondary) }
                    }.frame(minHeight: 44)
                }.accessibilityHint("Xem tóm tắt trước khi khôi phục")
            }
        }
    }
}

private struct BackupCounts: View {
    let file: BackupFile
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { counts }
            VStack(alignment: .leading) { counts }
        }.font(.caption).monospacedDigit()
    }
    @ViewBuilder private var counts: some View {
        Label(String(file.summary.wallets), systemImage: "wallet.bifold").accessibilityLabel("\(file.summary.wallets) ví")
        Label(String(file.summary.categories), systemImage: "tag").accessibilityLabel("\(file.summary.categories) danh mục")
        Label(String(file.summary.transactions), systemImage: "arrow.left.arrow.right").accessibilityLabel("\(file.summary.transactions) giao dịch")
        Label(String(file.payload.budgets.count), systemImage: "target").accessibilityLabel("\(file.payload.budgets.count) hạn mức")
        Label(String(file.payload.recurringRules.count), systemImage: "calendar").accessibilityLabel("\(file.payload.recurringRules.count) quy tắc định kỳ")
    }
}

@MainActor
struct RestoreSummaryView: View {
    let candidate: BackupScreenStore.PendingRestore
    @ObservedObject var store: BackupScreenStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var current: BackupValidator.Validated?
    var body: some View {
        List {
            Section("So sánh dữ liệu") {
                if let current {
                    Card { VStack(alignment: .leading, spacing: 8) { Text("Hiện tại").font(.headline); BackupCounts(file: current.file); AmountText(amount: current.totalBalance, style: .title2.bold()) } }
                } else { Text("Chưa đọc được tóm tắt hiện tại").foregroundStyle(.secondary) }
                Card { VStack(alignment: .leading, spacing: 8) {
                    Text("Trong file").font(.headline)
                    BackupCounts(file: candidate.summary.file)
                    AmountText(amount: candidate.summary.totalBalance, style: .title2.bold())
                    if let first = candidate.summary.firstDate, let last = candidate.summary.lastDate { TrendBadge(delta: "\(TransactionPresentation.shortDate(first)) → \(TransactionPresentation.shortDate(last))") }
                } }
                ForEach(candidate.summary.file.payload.wallets, id: \.id) { wallet in
                    Text("\(wallet.name): \(MoneyFormatter.string(from: candidate.summary.file.summary.expectedBalances[wallet.id] ?? 0))")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Callout(level: .danger, title: "Thay thế toàn bộ dữ liệu", message: "App tạo bản PreRestore và kiểm tra số dư trước khi lưu.")
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button(role: .destructive) { confirm = true } label: { Text("Thay thế toàn bộ và khôi phục").frame(minHeight: 44) }
            }
        }
        .task { current = try? BackupValidator.validate(store.scheduler.exporter.capture()) }
        .navigationTitle("Xác nhận khôi phục")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { store.error = nil; dismiss() } } }
        .confirmationDialog("Thay thế toàn bộ dữ liệu?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Khôi phục", role: .destructive) { store.restoreConfirmed(candidate) }
            Button("Hủy", role: .cancel) { }
        }
    }
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed && error == nil) }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private struct BackupPasswordView: View {
    @ObservedObject var store: BackupScreenStore
    let request: BackupScreenStore.PasswordRequest
    private enum Field: Hashable { case password }
    @FocusState private var focus: Field?
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(request.name).font(.caption).fixedSize(horizontal: false, vertical: true)
                SecureField("Mật khẩu backup", text: $password).focused($focus, equals: .password).submitLabel(.done).onSubmit { focus = nil }.textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44)
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if store.unlockingBackup { ProgressView("Đang giải mã…") }
                Button("Mở bản sao lưu") { store.unlockBackup(password: password); password = "" }.frame(minHeight: 44).disabled(password.isEmpty || store.unlockingBackup)
                Text("Sai mật khẩu hoặc file bị sửa đều không mở được. Dữ liệu hiện tại được giữ nguyên.").font(.footnote).foregroundStyle(.secondary)
            }.scrollDismissesKeyboard(.interactively)
                .keyboardDoneButton($focus)
                .navigationTitle("Mở backup mã hóa")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.frame(minHeight: 44) } }
        }
    }
}
