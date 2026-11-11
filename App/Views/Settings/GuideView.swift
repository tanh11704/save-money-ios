import SwiftUI

struct GuideView: View {
    var body: some View {
        List {
            topic("Ghi nhanh một khoản", icon: "plus.circle", tint: .accentColor,
                  text: "Nhập tiền → chọn danh mục → Lưu. Dùng +, − để gộp các khoản; không cần bấm = trước khi lưu.")
            topic("Chuyển tiền giữa các ví", icon: "arrow.left.arrow.right", tint: .blue,
                  text: "Vào Ví → Chuyển. Chọn hai ví, nhập tiền và xem số dư trước/sau rồi xác nhận.")
            topic("Sổ nợ và trả hộ", icon: "person.2", tint: .teal,
                  text: "Vào Ví → Sổ nợ để thêm người, cho vay hoặc trả nợ. Người khác trả hộ: ghi khoản Chi từ người đó.")
            topic("Ngân sách", icon: "target", tint: .orange,
                  text: "Vào Ví → Ngân sách để đặt hạn mức tháng. Cảnh báo 80% và 100% cần quyền gửi thông báo.")
            topic("Giữ bản sao lưu", icon: "externaldrive", tint: .green,
                  text: "App tự sao lưu. Chia sẻ bản mới ra iCloud Drive trong Cài đặt. Khôi phục sẽ thay thế dữ liệu hiện tại.")
            DisclosureGroup {
                Text("Giữ mật khẩu ở nơi an toàn ngoài iPhone.")
                Text("Quên mật khẩu sẽ không mở được bản sao lưu đã mã hóa.")
                    .fontWeight(.semibold).foregroundStyle(Color("Expense"))
            } label: { IconRow(icon: "lock.shield", tint: .purple, title: "Mã hóa bản sao lưu") }
            topic("Phím tắt và Siri", icon: "square.stack.3d.up", tint: .purple,
                  text: "Mở ứng dụng Phím tắt và tìm SaveMoney. Phím tắt chỉ mở màn hình; bạn vẫn mở khóa và bấm Lưu.")
        }
        .navigationTitle("Hướng dẫn nhanh")
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private func topic(_ title: String, icon: String, tint: Color, text: String) -> some View {
        DisclosureGroup {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } label: { IconRow(icon: icon, tint: tint, title: title) }
    }
}
