import SwiftUI

struct BackupEncryptionView: View {
    @ObservedObject var store: BackupScreenStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var oldPassword = ""
    @State private var recorded = false
    @State private var reencrypt = false
    @State private var busy = false
    @State private var disabling = false
    @State private var message: String?
    private var enabled: Bool { store.scheduler.exporter.protection.enabled }
    private enum Field: Hashable { case old, password, confirmation }
    @FocusState private var focus: Field?
    var body: some View {
        Form {
            Illustration(name: "illus-encryption")
            Section("Mã hóa bản sao lưu") {
                Text(enabled ? "Đang bật: mọi bản mới đều mã hóa, kể cả trước khôi phục." : "Đang tắt. Bật sẽ mã hóa cả các bản rõ đang có trong Backups/ và tạo một bản mới đã kiểm tra.")
                Callout(level: .danger, title: "Không thể lấy lại mật khẩu", message: "Quên mật khẩu sẽ không mở được file mã hóa.")
                Callout(level: .warning, title: "Giữ mật khẩu ngoài máy", message: "Đổi Apple ID ký SideStore hoặc cài lại app có thể mất khóa Keychain. Khi đó cần mật khẩu để khôi phục.")
                Callout(level: .info, title: "File cũ giữ mật khẩu cũ", message: "Chỉ đổi khi chọn mã hóa lại. Tắt mã hóa không giải mã file cũ.")
            }
            if enabled {
                Section("Mật khẩu hiện tại") {
                    SecureField("Mật khẩu cũ / cần kiểm tra", text: $oldPassword).focused($focus, equals: .old).submitLabel(.next).onSubmit { focus = .password }.frame(minHeight: 44)
                    Button("Kiểm tra mật khẩu") { verifyPassword() }.frame(minHeight: 44).disabled(busy || oldPassword.isEmpty)
                }
            }
            Section(enabled ? "Đổi mật khẩu" : "Bật mã hóa") {
                SecureField("Mật khẩu mới (ít nhất 10 ký tự)", text: $password).focused($focus, equals: .password).submitLabel(.next).onSubmit { focus = .confirmation }.frame(minHeight: 44)
                SecureField("Nhập lại mật khẩu mới", text: $confirmation).focused($focus, equals: .confirmation).submitLabel(.done).onSubmit { focus = nil }.frame(minHeight: 44)
                Toggle("Tôi đã ghi mật khẩu ở nơi an toàn ngoài iPhone này", isOn: $recorded).frame(minHeight: 44)
                if enabled { Toggle("Mã hóa lại các bản đang giữ bằng mật khẩu mới", isOn: $reencrypt).frame(minHeight: 44) }
                if busy { ProgressView("Đang tạo khóa và kiểm tra backup…") }
                Button(enabled ? "Đổi mật khẩu" : "Bật và tạo backup mã hóa") { activate() }.frame(minHeight: 44)
                    .disabled(busy || !recorded || password.precomposedStringWithCanonicalMapping.count < 10 || password.precomposedStringWithCanonicalMapping != confirmation.precomposedStringWithCanonicalMapping || (enabled && oldPassword.isEmpty))
                if enabled { Button("Tắt mã hóa", role: .destructive) { disabling = true }.frame(minHeight: 44).disabled(busy) }
            }
            if let message { Text(message).fixedSize(horizontal: false, vertical: true) }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton($focus)
        .navigationTitle("Mã hóa backup")
        .confirmationDialog("Tắt mã hóa backup mới?", isPresented: $disabling, titleVisibility: .visible) {
            Button("Tắt mã hóa", role: .destructive) {
                do { try BackupEncryptionManager(exporter: store.scheduler.exporter).disable(); store.refresh(); message = "Đã tắt. File cũ vẫn cần mật khẩu cũ." }
                catch { message = error.localizedDescription }
            }
        } message: { Text("Khóa trên máy sẽ bị xóa. Hãy chắc chắn bạn đã ghi mật khẩu cũ ở ngoài iPhone.") }
    }
    private func activate() {
        let password = self.password, old = oldPassword, wasEnabled = enabled, reencrypt = self.reencrypt
        busy = true; message = nil
        Task {
            defer { busy = false; self.password = ""; confirmation = ""; oldPassword = "" }
            do {
                let key = try await Task.detached { try BackupCrypto.deriveKey(password: password) }.value
                let manager = BackupEncryptionManager(exporter: store.scheduler.exporter)
                if wasEnabled { try manager.changePassword(oldPassword: old, key: key, reencrypt: reencrypt) }
                else { try manager.enable(key: key) }
                store.refresh(); message = "Đã tạo và mở kiểm tra bản backup mã hóa. Hãy chia sẻ bản mới ra ngoài."
            } catch { message = error.localizedDescription }
        }
    }
    private func verifyPassword() {
        let password = oldPassword; busy = true
        Task {
            defer { busy = false; oldPassword = "" }
            do {
                let entries = try BackupCatalog.entries(in: store.scheduler.exporter.directory, protection: store.scheduler.exporter.protection)
                guard let url = entries.first(where: \.encrypted)?.url else { throw BackupError.unreadable }
                let data = try Data(contentsOf: url)
                _ = try await Task.detached { try BackupValidator.read(BackupCrypto.open(data, password: password)) }.value
                store.scheduler.defaults.set(Date(), forKey: "SaveMoney.lastBackupPasswordCheck")
                store.refresh(); message = "Mật khẩu đúng; checksum và dữ liệu hợp lệ."
            } catch { message = error.localizedDescription }
        }
    }
}
