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
            Section("Sao lưu") {
                backupStatus
                if let error = store.error ?? store.scheduler.lastError { Text(error).foregroundStyle(.red) }
                if let message = store.message { Text(message).foregroundStyle(.secondary) }
                Button { store.backupNow() } label: { Label("Sao lưu ngay", systemImage: "externaldrive").frame(minHeight: 44) }
                Button {
                    if let latest = store.latest { sharing = ShareItem(url: latest) }
                } label: { Label("Chia sẻ bản mới nhất", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                    .disabled(store.latest == nil)
                NavigationLink { backupList } label: { Text("Danh sách bản sao lưu").frame(minHeight: 44) }
                Button { importing = true } label: { Text("Khôi phục từ file").frame(minHeight: 44) }
                Text("Bật Cài đặt → [tên bạn] → iCloud → Sao lưu iCloud trên iPhone. Nhớ chép file JSON sang iCloud Drive.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("File JSON chưa mã hóa và có thể đọc từ ứng dụng Tệp dù app đang khóa.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section { NavigationLink { CSVExportView() } label: { Text("Xuất CSV").frame(minHeight: 44) } }
            Section("Kiểm tra dữ liệu") {
                if store.scheduler.defaults.object(forKey: "SaveMoney.lastIntegrityCheck") != nil && !store.scheduler.defaults.bool(forKey: "SaveMoney.lastIntegrityHealthy") {
                    Label("Kiểm tra gần nhất có lỗi. Hãy xem kết quả và sao lưu trước khi sửa.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                NavigationLink { IntegrityView(store: store) } label: { Text("Kiểm tra dữ liệu").frame(minHeight: 44) }
            }
            Section("Bảo mật") {
                Toggle("Khóa bằng Face ID", isOn: Binding(get: { lock.enabled }, set: { value in Task { _ = await lock.setEnabled(value) } }))
                    .frame(minHeight: 44).disabled(lock.state == .authenticating)
                Text("Dùng Face ID hoặc mật mã máy. Khóa khi mở app và khi quay lại sau hơn 30 giây ở nền.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message = lock.message { Text(message).foregroundStyle(.red) }
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
        .sheet(item: $store.pending) { pending in
            NavigationStack {
                RestoreSummaryView(candidate: pending, store: store)
            }
        }
    }

    private var backupStatus: some View {
        let health = store.health
        return VStack(alignment: .leading, spacing: 8) {
            Label(health.title, systemImage: health.level == .good ? "checkmark.shield" : "exclamationmark.triangle.fill").font(.headline)
            ForEach(health.reasons, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            if let date = health.lastBackup { Text("Backup gần nhất: " + TransactionPresentation.shortDate(date)) }
            Text("\(health.fileCount) bản, \(ByteCountFormatter.string(fromByteCount: health.totalBytes, countStyle: .file))")
            if let kind = health.lastBackupKind { Text("Loại gần nhất: " + (kind == .auto ? "Tự động" : kind == .manual ? "Thủ công" : "Trước khôi phục")) }
            if let age = store.scheduler.externalCopyAge { Text("Bản chép ra ngoài gần nhất: \(age) ngày trước") }
        }
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
                        Text("\(entry.file.summary.wallets) ví, \(entry.file.summary.categories) danh mục, \(entry.file.summary.transactions) giao dịch, \(entry.file.payload.budgets.count) hạn mức")
                    }.frame(minHeight: 44)
                }.accessibilityHint("Xem tóm tắt trước khi khôi phục")
            }
        }
    }
}

@MainActor
private struct RestoreSummaryView: View {
    let candidate: BackupScreenStore.PendingRestore
    @ObservedObject var store: BackupScreenStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        List {
            Section("Dữ liệu trong file") {
                Text("\(candidate.summary.file.summary.wallets) ví")
                Text("\(candidate.summary.file.payload.recurringRules.count) giao dịch định kỳ")
                Text("\(candidate.summary.file.payload.budgets.count) hạn mức")
                Text("\(candidate.summary.file.summary.categories) danh mục")
                Text("\(candidate.summary.file.summary.transactions) giao dịch")
                Text("Tổng số dư: \(MoneyFormatter.string(from: candidate.summary.totalBalance))")
                    .fixedSize(horizontal: false, vertical: true)
                if let first = candidate.summary.firstDate, let last = candidate.summary.lastDate {
                    Text("Từ \(TransactionPresentation.shortDate(first)) đến \(TransactionPresentation.shortDate(last))")
                }
                ForEach(candidate.summary.file.payload.wallets, id: \.id) { wallet in
                    Text("\(wallet.name): \(MoneyFormatter.string(from: candidate.summary.file.summary.expectedBalances[wallet.id] ?? 0))")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Text("Khôi phục sẽ thay thế toàn bộ dữ liệu. App sẽ tạo bản PreRestore và kiểm tra số dư trước khi lưu.")
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button(role: .destructive) { confirm = true } label: { Text("Thay thế toàn bộ và khôi phục").frame(minHeight: 44) }
            }
        }
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
