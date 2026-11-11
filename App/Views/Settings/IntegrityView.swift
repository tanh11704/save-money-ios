import SwiftUI

struct IntegrityView: View {
    @ObservedObject var store: BackupScreenStore
    var body: some View {
        List {
            Button { store.checkIntegrity() } label: { Text("Kiểm tra ngay").frame(minHeight: 44) }.disabled(store.checkingIntegrity)
            if store.checkingIntegrity { ProgressView("Đang kiểm tra dữ liệu và bản sao lưu…") }
            if let report = store.integrityReport {
                Text(report.isHealthy ? "Dữ liệu ổn: \(report.transactionCount) giao dịch, \(report.backupFilesChecked) bản backup hợp lệ" : "Dữ liệu có vấn đề cần xem lại.")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                ForEach([IntegrityIssue.Severity.error, .warning], id: \.self) { severity in
                    Section(severity == .error ? "Lỗi" : "Cần chú ý") {
                        ForEach(report.issues.filter { $0.severity == severity }) { issue in
                            Text(issue.message).foregroundStyle(severity == .error ? Color.red : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text("Chỉ kiểm tra, không tự sửa hay khôi phục dữ liệu.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Kiểm tra dữ liệu")
    }
}
