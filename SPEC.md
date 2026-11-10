# SPEC.md — Ứng dụng quản lý chi tiêu cá nhân (iPhone)

## 1. Tổng quan

- Ứng dụng cá nhân, một người dùng, chỉ chạy trên iPhone, dữ liệu lưu cục bộ.
- Công nghệ: Swift, SwiftUI, SwiftData, nhắm vào bản iOS mới nhất mà iPhone của chủ dự án chạy được.
- Không dùng thư viện bên ngoài nếu chưa hỏi chủ dự án.
- Phân phối: cài qua SideStore (Apple ID miễn phí, ký lại mỗi 7 ngày). Có thể nâng lên tài khoản Developer trả phí sau này.
- Ngôn ngữ giao diện: tiếng Việt. Tiền tệ: VND.
- Ưu tiên cao nhất: **không bao giờ làm mất hoặc làm sai dữ liệu tài chính**. Tốc độ nhập liệu là ưu tiên thứ hai.

## 2. Quy tắc bắt buộc (áp dụng mọi giai đoạn)

### Về tiền
1. Số tiền lưu bằng `Int64`, đơn vị đồng. Cấm dùng `Double` hoặc `Float` cho tiền.
2. `Transaction.amount` luôn dương. Hướng thu/chi do `kind` quyết định.
3. Số dư ví **không lưu cứng**. Luôn tính: `openingBalance + tổng thu − tổng chi + tiền chuyển đến − tiền chuyển đi`.
4. Giao dịch chuyển tiền (`transfer`) **không tính vào thu hoặc chi** trong mọi thống kê, ngân sách, biểu đồ.
5. Chuyển tiền phải có ví nguồn và ví đích khác nhau, không có danh mục.
6. Mọi logic tính tiền nằm trong `Services/`, không viết trong View, và phải có unit test.

### Về dữ liệu
7. Ví và danh mục không bị xóa thật: dùng cờ `isArchived`. Ví/danh mục đã archive vẫn hiện trong lịch sử cũ, nhưng không xuất hiện khi chọn lúc nhập giao dịch mới.
8. Mọi thuộc tính của model có giá trị mặc định hoặc là optional (để sau này có thể bật đồng bộ iCloud).
9. Mọi thay đổi schema phải đi kèm kế hoạch migration và **chỉ làm sau khi đã xuất backup**.
10. Hiển thị ngày giờ theo múi giờ Asia/Saigon. Thống kê "theo tháng" tính theo lịch tháng trong múi giờ này.

### Về quy trình làm việc
11. Đọc file này ở đầu mỗi phiên làm việc.
12. Chỉ làm đúng giai đoạn và bước hiện tại. Không làm trước tính năng của giai đoạn sau.
13. Mỗi bước nhỏ: viết code, chạy test, báo kết quả, rồi dừng để chủ dự án commit.
14. Nếu yêu cầu mâu thuẫn với quy tắc ở đây, nêu rõ mâu thuẫn và hỏi lại, không tự chọn.
15. Không dùng dữ liệu tài chính thật khi test. Chỉ dùng dữ liệu mẫu.
16. Khi gặp lỗi build lạ hoặc API không chắc có tồn tại, nói rõ là chưa chắc, không bịa API.

## 3. Mô hình dữ liệu

```swift
enum TransactionKind: String, Codable { case income, expense, transfer }

@Model final class Wallet {
    var id: UUID = UUID()
    var name: String
    var openingBalance: Int64
    var isArchived: Bool = false
    var createdAt: Date = Date()
}

@Model final class Category {
    var id: UUID = UUID()
    var name: String
    var kindRaw: String        // income hoặc expense
    var icon: String
    var isArchived: Bool = false
}

@Model final class Transaction {
    var id: UUID = UUID()
    var amount: Int64          // luôn dương
    var kindRaw: String
    var date: Date
    var note: String = ""
    var wallet: Wallet?        // ví nguồn
    var toWallet: Wallet?      // chỉ khi chuyển tiền
    var category: Category?    // nil khi chuyển tiền
}
```

Các giai đoạn sau sẽ thêm `Budget`, `RecurringRule` (giai đoạn 2). Chưa tạo trước.

## 4. Cấu trúc thư mục

```
App/
  Models/      Wallet, Category, Transaction
  Services/    BalanceCalculator, StatsService, BackupService
  Views/       Transactions/, Wallets/, Categories/, Stats/, Settings/
  Tests/       BalanceCalculatorTests, StatsTests, BackupTests
```

## 5. Giai đoạn 1 — MVP: Quản lý thu chi và bảo vệ dữ liệu

### Tính năng
- Ghi thu nhập, chi tiêu, chuyển tiền giữa các ví
- Quản lý ví (tiền mặt, ngân hàng, thẻ) và danh mục thu/chi, có archive
- Lịch sử giao dịch: xem, sửa, xóa, lọc theo ví, danh mục, tháng
- Tổng số dư và số dư từng ví
- Thống kê theo tháng: tổng thu, tổng chi, chênh lệch, chi theo danh mục
- Khóa ứng dụng bằng Face ID (có mật mã dự phòng của máy)
- **Backup và restore đầy đủ (xem mục 8), bắt buộc xong trước khi nhập dữ liệu thật**

### Yêu cầu nhập liệu nhanh
- Mở app là vào ngay màn hình thêm giao dịch được
- Thêm giao dịch tối đa 3 lần chạm cho trường hợp thông thường (số tiền, danh mục gần dùng, lưu)
- Nhớ ví và danh mục dùng gần nhất
- Bàn phím số, định dạng tiền có dấu phân cách hàng nghìn khi gõ

### Thứ tự thực hiện
1. `BalanceCalculator` + unit test (chưa làm giao diện)
2. Màn hình thêm giao dịch và danh sách giao dịch
3. Quản lý ví và danh mục
4. `StatsService` + màn hình thống kê tháng
5. `BackupService` + màn hình sao lưu + test vòng tròn
6. Face ID
7. Chủ dự án chạy thử với dữ liệu mẫu, thực hiện checklist mục 9

### Unit test bắt buộc
- Ví không có giao dịch: số dư bằng `openingBalance`
- Nhiều giao dịch thu chi hỗn hợp
- Chuyển tiền: ví nguồn giảm, ví đích tăng, tổng số dư tất cả ví không đổi
- Chuyển tiền không xuất hiện trong tổng thu, tổng chi, thống kê danh mục
- Giao dịch thuộc ví hoặc danh mục đã archive vẫn được tính
- Số tiền rất lớn không tràn `Int64` trong các phép cộng thông thường
- Ranh giới tháng: giao dịch lúc 23:59 ngày cuối tháng và 00:00 ngày đầu tháng (múi giờ Asia/Saigon)

## 6. Giai đoạn 2 — Ngân sách và phân tích

(Chỉ bắt đầu sau khi giai đoạn 1 đã dùng ổn định với dữ liệu thật vài tuần.)

- Hạn mức ngân sách theo danh mục và theo tháng
- Cảnh báo khi đạt 80% và 100% hạn mức, dùng thông báo cục bộ
- Biểu đồ chi tiêu (Swift Charts): theo danh mục, theo ngày trong tháng
- So sánh tháng này với tháng trước
- Giao dịch định kỳ: **sinh giao dịch khi mở app** (kiểm tra các lần đến hạn chưa được sinh), không dựa vào tác vụ nền. Mỗi lần sinh phải chống trùng.
- Thêm `Budget`, `RecurringRule` vào schema: **xuất backup trước khi đổi schema**, viết migration, thử trên bản sao.

## 7. Giai đoạn 3 — Bảo vệ và duy trì nâng cao

- Mã hóa file backup bằng mật khẩu (CryptoKit, AES-GCM, khóa dẫn xuất từ mật khẩu). Phải có cách khôi phục rõ ràng, và cảnh báo người dùng rằng quên mật khẩu là mất file.
- Kiểm tra toàn vẹn: tổng số dư khớp với tính từ giao dịch, không có giao dịch trỏ vào ví/danh mục không tồn tại, không có chuyển tiền thiếu ví đích, checksum file backup khớp
- Xuất CSV (giao dịch theo khoảng thời gian)
- Nhắc sao lưu nâng cao, báo cáo tình trạng backup
- Tối ưu iPhone: widget thêm giao dịch nhanh, App Shortcuts, tinh chỉnh Dynamic Type và chế độ tối
- Nếu sau này chuyển sang tài khoản Developer: cân nhắc CloudKit để đồng bộ tự động

## 8. Đặc tả backup và restore (bắt buộc trong MVP)

### Bối cảnh
App cài qua SideStore bằng Apple ID miễn phí, không dùng được iCloud trong app. Việc làm mới chữ ký có thể trễ hoặc hỏng. Chủ dự án dễ quên, nên backup phải tự động và không phụ thuộc trí nhớ. Có ba lớp bảo vệ:

### Lớp 1 — iCloud Backup của iPhone (cấu hình thủ công một lần)
Chủ dự án bật Cài đặt → [tên] → iCloud → Sao lưu iCloud. App không cần code cho lớp này, nhưng trang Cài đặt trong app phải có ghi chú nhắc việc này.

### Lớp 2 — Backup tự động trong app
- Định dạng: file JSON, có `schemaVersion`, `createdAt`, `appVersion`, danh sách ví, danh mục, giao dịch, và `checksum` (SHA-256 của phần dữ liệu)
- Kích hoạt: khi app chuyển sang nền nếu dữ liệu đã đổi kể từ backup gần nhất, và sau mỗi 20 giao dịch mới
- Lưu vào thư mục `Documents/Backups/`, tên file có ngày giờ, giữ 10 bản gần nhất, xóa bản cũ hơn
- Ghi file an toàn: ghi ra file tạm, kiểm tra đọc lại được và checksum khớp, rồi mới đổi tên thành file chính thức
- Nếu backup thất bại, hiện cảnh báo trong app

### Lớp 3 — Chép ra ngoài thiết bị
- Bật `UIFileSharingEnabled` và `LSSupportsOpeningDocumentsInPlace` trong Info.plist, để thư mục Backups hiện trong ứng dụng Tệp → Trên iPhone của tôi
- Nút "Chia sẻ bản backup mới nhất" mở Share Sheet để lưu vào iCloud Drive, AirDrop, hoặc gửi cho mình
- Thông báo cục bộ nhắc mỗi 14 ngày: "Chép file backup sang iCloud Drive"
- Banner trong app: "Backup gần nhất: X ngày trước". Vàng nếu hơn 7 ngày, đỏ nếu hơn 14 ngày. Một dòng riêng: "Bản chép ra ngoài gần nhất" cập nhật mỗi lần người dùng bấm chia sẻ

### Restore
- Chọn file từ Tệp hoặc từ danh sách bản backup trong app
- Kiểm tra trước khi nhập: `schemaVersion` được hỗ trợ, checksum khớp, cấu trúc hợp lệ. Nếu không hợp lệ thì từ chối và giữ nguyên dữ liệu hiện tại.
- Trước khi khôi phục, tự động tạo một bản backup của dữ liệu hiện tại
- Hiển thị tóm tắt trước khi xác nhận: số ví, số danh mục, số giao dịch, tổng số dư, khoảng ngày
- Chế độ khôi phục: thay thế toàn bộ. Thực hiện trong một transaction, lỗi thì hoàn tác
- Sau khôi phục, hiển thị so sánh số dư từng ví với số dư ghi trong file (nếu file có lưu)

### Test bắt buộc
- Vòng tròn: tạo dữ liệu mẫu, export, xóa hết, import, so sánh toàn bộ (số lượng, từng giao dịch, số dư mỗi ví) phải khớp tuyệt đối
- File bị sửa một ký tự: checksum phải phát hiện
- File có `schemaVersion` cao hơn app hỗ trợ: từ chối với thông báo rõ
- File rỗng, JSON hỏng, thiếu trường: từ chối, không làm thay đổi dữ liệu
- Giữ đúng 10 bản, xóa bản cũ nhất
- Restore thất bại giữa chừng: dữ liệu cũ còn nguyên

## 9. Checklist xác nhận trước khi nhập dữ liệu thật

Chủ dự án thực hiện, không phải LLM:

- [ ] Toàn bộ unit test đạt
- [ ] Cài bản dùng thật qua SideStore (không cài từ Xcode, vì bundle ID khác nhau và dữ liệu không chuyển sang nhau)
- [ ] Nhập vài giao dịch mẫu, bấm làm mới trong SideStore, dữ liệu còn nguyên
- [ ] Xuất backup, xóa app, cài lại, khôi phục, số dư từng ví khớp trước đó
- [ ] File backup xuất hiện trong ứng dụng Tệp và lưu được sang iCloud Drive
- [ ] iCloud Backup của iPhone đang bật
- [ ] Để qua ngày thứ 7 và xác nhận làm mới tự động hoạt động, hoặc đã có thói quen làm mới thủ công
- [ ] Thông báo nhắc backup đã hiện thử thành công
- [ ] Face ID khóa app hoạt động, mật mã dự phòng hoạt động

## 10. Lưu ý vận hành

- Chọn một đường cài duy nhất cho bản dùng thật. Đổi giữa Xcode và SideStore là đổi bundle ID, dữ liệu không đi theo, chỉ chuyển được bằng file backup.
- Apple ID miễn phí giới hạn 3 app đang hoạt động, SideStore tính là một. Nên dùng Apple ID riêng.
- Đợi vài ngày sau khi có bản iOS mới rồi mới cập nhật, vì SideStore có thể tạm hỏng.
- Nếu SideStore gây phiền, đường lui là nâng lên tài khoản Developer 99$/năm: thêm capability iCloud, dùng file backup để chuyển dữ liệu sang bản cài mới.
- Trước mọi thay đổi schema: xuất backup, rồi mới sửa.

## 11. Chưa làm (ngoài phạm vi)

Nhiều loại tiền tệ, ảnh hóa đơn, nhiều người dùng, đồng bộ đám mây, liên kết tài khoản ngân hàng, bản Android. Chỉ xem xét lại nếu chủ dự án yêu cầu rõ.
