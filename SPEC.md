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
    var recurrenceKey: String? = nil // <ruleID>.<yyyyMMdd>, giữ khi sửa giao dịch
    var wallet: Wallet?        // ví nguồn
    var toWallet: Wallet?      // chỉ khi chuyển tiền
    var category: Category?    // nil khi chuyển tiền
}
```

`Budget` thêm ở schema V2; schema V3 thêm `RecurringRule` và khóa định kỳ trên Transaction. V1 và V2 có model đóng băng riêng; migration nhẹ V1 → V2 → V3. Mọi thuộc tính mới có mặc định hoặc optional.

```swift
@Model final class RecurringRule {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var amount: Int64 = 1
    var note: String = ""
    var wallet: Wallet? = nil
    var toWallet: Wallet? = nil
    var category: Category? = nil
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    var interval: Int = 1
    var startDate: Date = Date()
    var endDate: Date? = nil
    var generatedThrough: Date? = nil
    var isPaused: Bool = false
    var createdAt: Date = Date()
}
```

## 4. Cấu trúc thư mục

```
App/
  Models/      Wallet, Category, Transaction, Budget, RecurringRule
  Services/    BalanceCalculator, StatsService, BackupService
  Views/       Transactions/, Wallets/, Categories/, Stats/, Budgets/, Recurring/, Settings/
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

- [x] Hạn mức tổng và theo danh mục chi, lặp hàng tháng; bản sửa có tháng bắt đầu để giữ lịch sử. Đặt/tắt từ Ví → Ngân sách, không thêm tab.
- [x] Tiến độ trong Thống kê theo tháng đang xem và số tiền còn/vượt trên chip danh mục chi. Tính cả danh mục đã lưu trữ; không tính thu/chuyển.
- [x] Cảnh báo 80% và 100% bằng thông báo cục bộ sau khi lưu thành công; mỗi scope/mốc/tháng chỉ gửi một lần, giữ key khi xóa/sửa giảm chi. Nhảy qua cả hai mốc gửi hai thông báo. Giao dịch tháng cũ không gửi.
- Hạ hạn mức xuống dưới số đã chi không gửi thông báo ngay và không báo bù các mốc đã vượt. Chỉ một lần lưu giao dịch thành công vượt mốc so với số chi trước lần lưu đó mới có thể báo, nếu scope/mốc/tháng chưa gửi.
- Khoản chi nhập lùi tháng trước không gửi thông báo; Thống kê và tiến độ ngân sách vẫn tính theo tháng của ngày giao dịch.
- Xin quyền thông báo bằng cơ chế ReminderService khi đặt hạn mức. Khi lưu giao dịch, không có quyền hoặc gửi lỗi thì im lặng, không chặn lưu.
- Tổng hạn mức danh mục lớn hơn hạn mức tổng: cảnh báo có chữ nhưng vẫn cho lưu. Trạng thái tiến độ luôn có chữ “Sắp hết”/“Đã vượt”, màu hệ thống chỉ hỗ trợ.
- [x] Biểu đồ Swift Charts theo ngày và vòng theo danh mục (top 5 + Khác). Số tiền Int64 được đổi sang Double chỉ để vẽ. Ngày không chi có cột 0; tháng không chi ẩn biểu đồ. Danh sách chữ, chú thích tên và nhãn VoiceOver đi kèm. Hạn mức tổng có đường trung bình cho phép/ngày (chia nguyên).
- [x] So sánh tháng hiện tại đến hết hôm nay với cùng số ngày tháng trước, kẹp cuối tháng ngắn. Tháng đã qua so cả tháng; có chữ Tăng/Giảm/Không đổi, số tiền có dấu, phần trăm có dấu được kẹp ±999,9%; gốc 0 hiện Mới.
- [x] Định kỳ ngày/tuần/tháng/năm, mỗi N, có ngày bắt đầu và kết thúc tùy chọn; quản lý từ Ví → Giao dịch định kỳ. Form xem trước các ngày tới và báo số giao dịch sẽ tạo ngay nếu bắt đầu trong quá khứ.
- [x] Sinh khi mở app hoặc quay lại foreground sau mở khóa; không chạy nền hay trong restore. Tối đa 400 lần/quy tắc/lượt; còn dư có ghi chú và tiếp tục lần mở sau. Lịch neo vào ngày bắt đầu, cuối tháng/năm nhuận được kẹp, giờ 00:00 Asia/Saigon.
- [x] Con trỏ `generatedThrough` và khóa `<ruleID>.<yyyyMMdd>` được lưu cùng giao dịch trong một save, lỗi rollback. Xóa giao dịch không lùi con trỏ, không sinh lại. Sửa quy tắc giữ con trỏ và chỉ ảnh hưởng các lần sau; có tạm dừng/tiếp tục, không xóa thật.
- Quy tắc có ví/danh mục đã lưu trữ hoặc không hợp lệ: không sinh, không đẩy con trỏ, có lý do trong danh sách. Sửa/khôi phục xong có thể sinh bù.
- Sau một đợt: đếm từng giao dịch vào scheduler backup, tải lại các màn hình và so ngân sách trước/sau cả đợt để gửi cảnh báo một lần, chỉ tháng hiện tại. Lịch sử có dấu Định kỳ và VoiceOver tương ứng.
- Đã xuất backup trước V3 theo xác nhận của chủ dự án; có test nâng store V1 chưa version và V2 lên V3 giữ dữ liệu/số dư/hạn mức. Nghiệm thu cài đè trên máy thật vẫn cần thực hiện.

## 7. Giai đoạn 3 — Bảo vệ và duy trì nâng cao

- [x] Kiểm tra toàn vẹn chỉ đọc: dùng chung TransactionValidator, Budget.rule, RecurringValidator và BalanceCalculator; kiểm tra ID/khóa định kỳ, tham chiếu, số dư và backup. Giao dịch cũ thiếu danh mục là warning. Không tự sửa. File mã hóa thiếu khóa được đánh dấu chưa kiểm tra (warning).
- [x] Cài đặt có kiểm tra ngay và kết quả theo mức độ. Tự kiểm tra mỗi 7 ngày sau mở khóa; đọc file ở tác vụ riêng. Lưu ngày/healthy; có lỗi hiện trong Cài đặt, không gửi push.
- [x] CSV UTF-8 BOM, RFC 4180, CRLF, số nguyên và số có dấu; chống chèn công thức ở ô chữ. Chọn khoảng ngày Asia/Saigon, có preset, đếm giao dịch và chia sẻ file tạm. CSV không phải backup, không được mã hóa theo cài đặt backup và không dùng để restore.
- [x] BackupHealth: có chữ/lý do, số bản/dung lượng/loại, mốc 7/14 ngày, kiểm tra 30 ngày, chưa chép ra ngoài trên 50 giao dịch, lỗi backup và thay đổi chưa backup. Có badge Cài đặt khi critical.
- [x] Hai lỗi auto liên tiếp gửi nhắc tối đa một lần/ngày; thành công reset chuỗi lỗi. Chia sẻ thành công reset nhắc +14, +21, +24, +27 ngày rồi dừng, hủy lịch +28 cũ. Mật khẩu cần kiểm tra lại sau 90 ngày.
- [x] Mã hóa AES-GCM-256 bằng CryptoKit; khóa dẫn xuất bằng **CommonCrypto CCKeyDerivationPBKDF, PBKDF2-HMAC-SHA256, 600.000 vòng**, salt 16 byte. NFC, tối thiểu 10 ký tự. Nonce ngẫu nhiên mỗi file, xác thực header bằng AAD, có known-answer test RFC 7914.
- Quyết định đã chốt: bật mã hóa áp dụng cho mọi backup Auto/Manual/PreRestore. Khi bật, chuyển cả bản rõ đang có sang mã hóa; chỉ báo thành công sau khi tạo và mở kiểm tra một bản mới. Thiếu/lỗi khóa Keychain thì bỏ qua backup và báo lỗi, **không ghi bản rõ**.
- Chỉ khóa đã dẫn xuất (không mật khẩu) được lưu Keychain AfterFirstUnlockThisDeviceOnly, không đồng bộ. Bật có xác nhận đã ghi mật khẩu ngoài iPhone; tắt xóa khóa. File cũ vẫn cần mật khẩu cũ. Đổi mật khẩu phải kiểm tra cũ, có tùy chọn mã hóa lại các bản đang giữ. Hoạt động lỗi được rollback, không xóa bản gốc trước khi kiểm tra bản thay thế.
- [x] 4 App Shortcuts mở app: Thêm chi/thu, Lịch sử, Thống kê. Không đọc số dư hay tự lưu; route giữ khi khóa và chỉ xử lý sau mở khóa. URL savemoney://add?kind=expense&amount=50000 có kiểm tra loại/số tiền.
- [x] K0: có target WidgetTrial chỉ để thử SideStore, không đọc dữ liệu, không App Group, không di chuyển store. IPA thử được đóng gói riêng theo INCLUDE_WIDGET_TRIAL=1. Người dùng chọn thử K0; **K1 chờ kết quả cài và làm mới chữ ký trên iPhone thật**, chưa triển khai widget hoàn chỉnh.
- [x] Có preview và ảnh render AX5 tối / chữ nhỏ nhất sáng; tăng chiều cao biểu đồ, cho tiền/biểu thức xuống dòng, giữ phím 000 đọc được và lưới bàn phím trong chiều rộng màn hình. Checklist QA ghi rõ giới hạn ảnh tĩnh, các bước VoiceOver/tương phản/cuộn/chạm vẫn cần nghiệm thu thiết bị.
- [ ] CloudKit ngoài phạm vi, chỉ xem xét khi chuyển tài khoản Developer trả phí.

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

### Hạn mức và định kỳ trong backup v3
- Backup v2 bổ sung `budgets` (id, scopeRaw, categoryID, limit, startYear, startMonth, isArchived, createdAt), được băm cùng payload; summary thêm số hạn mức.
- Vẫn đọc/khôi phục v1, coi hạn mức là rỗng và giữ nguyên cách mã hóa checksum v1. Bản xuất mới là v3, vẫn đọc v1/v2 và từ chối phiên bản lớn hơn 3.
- Kiểm tra hạn mức dương trong phạm vi nhập, tháng hợp lệ, scope tổng không có danh mục; scope danh mục phải trỏ tới danh mục chi tồn tại. Không trùng scope và tháng bắt đầu.
- V3 thêm `recurringRules` và `TransactionRecord.recurrenceKey` trong checksum. Bản v1/v2 thiếu các trường này được coi là rỗng/nil, giữ nguyên checksum cũ. Kiểm tra chu kỳ ≥1, số tiền 1…max, tham chiếu đúng ví/danh mục/loại, ngày kết thúc ≥ bắt đầu và không trùng recurrenceKey.
- Restore xóa/chèn quy tắc định kỳ trong cùng transaction; giữ con trỏ và khóa theo file. Lần mở sau chỉ sinh các lần còn đến hạn; lỗi restore giữ nguyên cả quy tắc, khóa và dữ liệu cũ. Tóm tắt có số giao dịch định kỳ. Giữ golden-v1/v2/v3.
- Khôi phục thay thế xóa cả hạn mức trong cùng transaction, rollback toàn bộ nếu lỗi. Tóm tắt xác nhận có số hạn mức. Giữ cả golden-v1 và golden-v2 trong test.

### Phong bì mã hóa (không đổi schema SwiftData hay backup v3 bên trong)
- Đuôi .savemoney, tên hậu tố -encrypted. JSON có format = savemoney-backup-encrypted, envelopeVersion = 1, kdf { name = PBKDF2-HMAC-SHA256, iterations, salt base64 }, cipher = AES-GCM-256, keyID (8 byte SHA256 đầu dạng hex), createdAt (Int64 ms), sealed (combined nonce + ciphertext + tag base64).
- AAD là JSON chuẩn tắc sortedKeys/withoutEscapingSlashes của toàn bộ header, trừ sealed. Từ chối version/cipher/KDF lạ, salt không đủ 16 byte hoặc iterations ngoài 100.000…10.000.000 **trước** dẫn xuất.
- Ghi file tạm đã mã hóa, mở bằng khóa Keychain và kiểm tra BackupValidator/checksum trước đổi tên. Không có khóa thì dừng; không fallback plaintext. Catalog/rotation tính cả file mã hóa chưa có khóa, giữ 10 bản chính và 5 PreRestore.
- Restore nhận file thường v1/v2/v3 không hỏi mật khẩu. File mã hóa có keyID khớp thì mở bằng Keychain; thiếu khóa thì sheet nhập mật khẩu. Sai mật khẩu/file bị sửa cùng thông báo, dữ liệu hiện tại giữ nguyên. Giải mã xong vẫn chạy đủ validator và xác nhận tóm tắt, tạo PreRestore theo cùng cài đặt mã hóa rồi mới thay dữ liệu.
- Quên mật khẩu sau khi mất khóa Keychain (xóa/cài lại hoặc đổi Apple ID ký app) thì không khôi phục được file. Bắt buộc ghi mật khẩu ra ngoài máy và diễn tập khôi phục bằng mật khẩu trước dùng thật.

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
- [ ] Đã ghi mật khẩu backup ra ngoài iPhone
- [ ] Khôi phục được bản mã hóa sau khi xóa/cài lại app, bằng mật khẩu
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

## 12. Quy tắc giao diện

### Điều hướng
- TabView, mở app vào tab "Thêm". Bước 2 chỉ có 2 tab: "Thêm" và "Lịch sử". Các tab Ví, Thống kê, Cài đặt thêm ở bước sau.
- Sửa giao dịch mở bằng sheet từ danh sách, dùng lại đúng form của tab "Thêm".

### Ô nhập số tiền
- Dùng bàn phím số tự vẽ (không dùng TextField), gồm các phím 0-9, "000", xóa lùi. Không có con trỏ, không dán chữ, không có chỗ để gõ ký tự lạ.
- State gốc là `Int64`. Chuỗi hiển thị luôn được sinh ra từ `Int64`, không bao giờ ngược lại.
- Mỗi toán hạng tối đa 999.999.999.999 đ. Vượt thì bỏ qua lần bấm đó.
- Chỉ form giao dịch có bàn phím 4 cột với `+`, `−`, `=`, `C`; form ví và hạn mức giữ bàn phím số 3 cột. Cộng/trừ từ trái sang phải bằng Int64, kiểm tra tràn số và bỏ qua lần bấm gây tràn.
- Kết quả tạm thời được âm hoặc bằng 0. Chỉ lưu khi kết quả trong 1…999.999.999.999; ngoài khoảng này nút Lưu vô hiệu và có giải thích. Không bắt bấm `=` trước khi lưu, kể cả đang chờ toán tử. `=` gộp biểu thức nếu kết quả không âm; `C` xóa hết.
- Biểu thức sinh từ các toán hạng Int64, không parse ngược chuỗi hiển thị. Đổi Chi/Thu/Chuyển giữ biểu thức, lưu giao dịch mới thì xóa biểu thức.
- Định dạng: dấu chấm phân cách hàng nghìn, hậu tố "₫", ví dụ `1.250.000 ₫`. Dùng `monospacedDigit`.
- Mọi định dạng tiền đi qua một `MoneyFormatter` duy nhất trong Services.

### Bố cục màn hình Thêm (từ trên xuống)
1. Chọn loại: Chi / Thu / Chuyển (segmented, mặc định Chi)
2. Số tiền cỡ lớn
3. Danh mục (lưới chip, mục dùng gần nhất lên đầu). Khi chọn Chuyển: thay bằng "Từ ví" và "Đến ví"
4. Ví (chip, hiện kèm số dư hiện tại của ví)
5. Ngày: chip "Hôm nay", "Hôm qua", "Chọn ngày"
6. Ghi chú (không bắt buộc, thu gọn mặc định)
7. Bàn phím số và nút Lưu nằm cuối màn hình, vùng ngón cái với tới

### Hành vi
- Lưu xong: rung nhẹ, hiện thông báo ngắn "Đã lưu", xóa số tiền, giữ nguyên loại/ví/danh mục để nhập tiếp. Không chuyển tab, không hiện alert.
- Nút Lưu bị vô hiệu khi dữ liệu chưa hợp lệ, kèm dòng giải thích ngắn bằng tiếng Việt ngay dưới (không dùng alert).
- Đổi loại sang Chuyển: xóa danh mục. Đổi từ Chuyển sang loại khác: xóa ví đích.
- Ví đích không được trùng ví nguồn: ví đã chọn ở "Từ ví" bị ẩn khỏi "Đến ví".
- Ví/danh mục đã archive không hiện khi chọn mới, nhưng vẫn hiện đúng khi xem hoặc sửa giao dịch cũ.
- Nhớ ví và danh mục dùng gần nhất theo từng loại (thu, chi, chuyển), lưu ID trong UserDefaults.
- Xóa giao dịch: vuốt và có hộp xác nhận.

### Danh sách lịch sử
- Nhóm theo ngày (múi giờ Asia/Saigon), mới nhất trước. Tiêu đề: "Hôm nay", "Hôm qua", sau đó "Thứ ba, 10/11/2026".
- Mỗi dòng: icon danh mục, tên danh mục (hoặc "Chuyển: A → B"), ghi chú và tên ví ở dòng phụ, số tiền căn phải.
- Chi hiện dấu "−", thu hiện dấu "+", chuyển không dấu và màu trung tính. Không dùng riêng màu để phân biệt, luôn có dấu.
- Trên cùng hiện tổng số dư (từ `BalanceCalculator`).
- Trạng thái rỗng: "Chưa có giao dịch. Sang tab Thêm để ghi khoản đầu tiên."

### Phong cách chung
- Chỉ dùng thành phần và màu hệ thống của SwiftUI, SF Symbols, Dynamic Type, hỗ trợ chế độ tối. Không tự dựng theme.
- Vùng chạm tối thiểu 44x44 pt.
- Mọi nhãn tiếng Việt, ngày giờ theo `vi_VN` và Asia/Saigon.
- VoiceOver: số tiền đọc là "một triệu hai trăm năm mươi nghìn đồng" hoặc tối thiểu có nhãn rõ loại giao dịch.
- Không animation phức tạp, không onboarding, không tính năng của bước sau.

## 13. Quy tắc quản lý ví và danh mục (Bước 3)

### Điều hướng
- Thêm tab "Ví" (tab thứ 3). Tab "Danh mục" không tách riêng: vào từ tab Ví qua mục "Quản lý danh mục", để thanh tab không quá đông.
- Thêm ví/danh mục mở bằng sheet. Sửa dùng lại đúng form thêm.
- Chưa thêm tab Thống kê và Cài đặt (bước sau).

### Tab Ví
- Trên cùng: "Tổng số dư" cỡ lớn, lấy từ `BalanceCalculator`, chỉ cộng các ví **chưa archive**...
  → **Quy tắc rõ ràng:** tổng số dư hiển thị mặc định gồm cả ví đã archive nếu số dư khác 0, để không có tiền "biến mất". Ví archive có số dư 0 thì không tính vào danh sách.
- Danh sách ví đang dùng: tên, loại (icon), số dư căn phải. Số dư âm hiện màu đỏ và dấu "−".
- Cuối danh sách: mục thu gọn "Đã lưu trữ (N)" chứa ví archive, mở ra xem được, có thao tác "Khôi phục".
- Nút "+" thêm ví. Vuốt dòng: "Lưu trữ" (không có "Xóa").
- Trạng thái rỗng: "Chưa có ví. Thêm ví đầu tiên để bắt đầu."

### Form ví
- Trường: Tên, Loại (Tiền mặt / Ngân hàng / Thẻ / Khác), Số dư ban đầu.
- Số dư ban đầu dùng lại bàn phím số tự vẽ và `MoneyFormatter` của bước 2. Cho phép âm (ví dụ thẻ tín dụng đang nợ) bằng công tắc "Đang nợ", không cho gõ dấu trừ.
- Tên: bắt buộc, tối đa 30 ký tự, cắt khoảng trắng hai đầu, không trùng tên ví khác (không phân biệt hoa thường, tính cả ví đã archive).
- **Sửa số dư ban đầu của ví đã có giao dịch:** cho phép, nhưng hiện cảnh báo "Số dư hiện tại của ví sẽ thay đổi theo", và hiện số dư trước và sau.

### Form danh mục
- Trường: Tên, Loại (Chi / Thu), Biểu tượng (lưới SF Symbols chọn sẵn, khoảng 30 icon).
- **Không cho đổi Loại (thu/chi) khi danh mục đã có giao dịch**: ô Loại bị khóa, kèm dòng giải thích. Muốn khác loại thì tạo danh mục mới.
- Tên: bắt buộc, tối đa 30 ký tự, không trùng trong cùng loại (không phân biệt hoa thường, tính cả đã archive).
- Danh sách danh mục chia hai mục "Chi" và "Thu", có mục thu gọn "Đã lưu trữ".

### Archive
- Lưu trữ ví/danh mục: hộp xác nhận ngắn nêu hậu quả: "Không hiện khi nhập mới. Lịch sử và số dư giữ nguyên."
- Không cho lưu trữ ví cuối cùng còn đang dùng (phải còn ít nhất một ví hoạt động).
- Lưu trữ ví có số dư khác 0: cho phép nhưng cảnh báo rõ số dư còn lại.
- Khôi phục: một chạm, không cần xác nhận.
- Không có chức năng xóa thật ở bất kỳ đâu.

### Dữ liệu mặc định (lần chạy đầu)
- Chỉ tạo khi cả ví và danh mục đều trống **và** cờ `didSeedDefaults` trong UserDefaults chưa bật. Bật cờ ngay sau khi tạo. Tránh tạo lại sau khi người dùng chủ động archive hết.
- Ví mặc định: "Tiền mặt" (số dư 0). Không tạo ví khác.
- Danh mục chi: Ăn uống, Đi lại, Nhà ở, Hóa đơn, Mua sắm, Sức khỏe, Giải trí, Khác.
- Danh mục thu: Lương, Thu nhập khác.
- Xóa hoàn toàn đoạn tạo dữ liệu mẫu tạm của bước 2.

### Phong cách chung
- Giữ các quy tắc ở mục 12: thành phần hệ thống, Dynamic Type, chế độ tối, vùng chạm 44pt, tiếng Việt, VoiceOver.
- Lỗi hiện dòng chữ đỏ ngay dưới trường, không dùng alert (trừ hộp xác nhận hành động).
- Không thêm: sắp xếp kéo thả, đổi màu danh mục. Ngân sách hiện vào từ tab Ví.

## 14. Quy tắc thống kê tháng (Bước 4)

### Phạm vi
- Thêm tab "Thống kê" (tab thứ 4). Chỉ thống kê **một tháng lịch** mỗi lần xem. Có biểu đồ ngày, vòng danh mục và so sánh cùng kỳ. Section Ngân sách nằm dưới biểu đồ ngày.
- Mọi phép tính nằm trong `StatsService`, dùng `LocalCalendar` (Asia/Saigon). View chỉ hiển thị.

### Định nghĩa số liệu
- **Tổng thu** = tổng `amount` các giao dịch `income` trong tháng.
- **Tổng chi** = tổng `amount` các giao dịch `expense` trong tháng.
- **Chênh lệch** = tổng thu − tổng chi (có thể âm).
- Giao dịch `transfer` **không tính** vào thu, chi, chênh lệch hay danh mục.
- Khoảng tháng: từ 00:00 ngày 1 (gồm) đến 00:00 ngày 1 tháng sau (loại trừ), giờ Asia/Saigon.
- Giao dịch thuộc ví/danh mục đã archive **vẫn được tính**.
- Chi theo danh mục: sắp xếp giảm dần theo số tiền, kèm phần trăm trên tổng chi (làm tròn 1 chữ số thập phân, chỉ để hiển thị, không dùng để tính tiếp). Danh mục tổng 0 thì không hiện. Giao dịch không có danh mục (dữ liệu lỗi) gom vào dòng "Không có danh mục", không bỏ qua.
- Thêm mục "Thu theo danh mục" tương tự, hiện bên dưới.
- Phép cộng dùng `Int64`, báo lỗi khi tràn, như `BalanceCalculator`.

### Bố cục (từ trên xuống)
1. Thanh chọn tháng: nút lùi "‹", nhãn "Tháng 11/2026", nút tiến "›". Không cho tiến quá tháng hiện tại. Chạm nhãn mở chọn tháng/năm. Có nút "Tháng này" khi đang xem tháng khác.
2. Thẻ tóm tắt: Tổng thu (+), Tổng chi (−), Chênh lệch (có dấu +/−). Không chỉ dùng màu, luôn có dấu.
3. "Chi theo danh mục": mỗi dòng gồm icon, tên, số tiền, phần trăm.
4. "Thu theo danh mục".
5. Chạm một dòng danh mục: mở danh sách giao dịch của danh mục đó trong tháng (chỉ xem, dùng lại dòng giao dịch của Lịch sử).

### Trạng thái
- Tháng không có giao dịch: "Tháng này chưa có giao dịch."
- Tháng có thu nhưng không có chi (hoặc ngược lại): vẫn hiện thẻ tóm tắt, mục trống ghi "Không có khoản chi/thu."
- Số liệu cập nhật ngay khi thêm, sửa, xóa giao dịch ở tab khác (dùng `@Query`, không cache thủ công).

### Phong cách chung
- Giữ quy tắc mục 12 và 13: thành phần hệ thống, Dynamic Type, chế độ tối, vùng chạm 44pt, tiếng Việt, VoiceOver (đọc "Tổng chi, một triệu hai trăm nghìn đồng").
- Dùng `MoneyFormatter` đã có. Cỡ chữ lớn nhất: bố cục xếp dọc, không cắt số tiền.
- Xuất CSV ở Cài đặt; chưa lọc theo ví.

## 15. Đặc tả kỹ thuật backup (Bước 5, chi tiết hóa mục 8)

### Định dạng file
- Tên: `SaveMoney-yyyyMMdd-HHmmss-{Auto|Manual|PreRestore}.json`
- `schemaVersion` ở đây là phiên bản **định dạng file backup**, độc lập với schema SwiftData.

```json
{
  "format": "savemoney-backup",
  "schemaVersion": 3,
  "createdAt": 1789000000000,
  "appVersion": "1.0 (1)",
  "checksum": "<sha256 hex của payload>",
  "summary": {
    "wallets": 2, "categories": 10, "transactions": 120, "budgets": 3, "recurringRules": 2,
    "expectedBalances": { "<walletId>": 1080000 }
  },
  "payload": {
    "wallets":      [{ "id", "name", "kind", "openingBalance", "isArchived", "createdAt" }],
    "categories":   [{ "id", "name", "kind", "icon", "isArchived" }],
    "transactions": [{ "id", "amount", "kind", "date", "note", "walletId", "toWalletId", "categoryId", "recurrenceKey" }],
    "budgets": [{ "id", "scopeRaw", "categoryID", "limit", "startYear", "startMonth", "isArchived", "createdAt" }],
    "recurringRules": [{ "id", "name", "kindRaw", "amount", "note", "walletId", "toWalletId", "categoryId", "frequencyRaw", "interval", "startDate", "endDate", "generatedThrough", "isPaused", "createdAt" }]
  }
}
```

### Quy tắc mã hóa dữ liệu
- Tiền là số nguyên `Int64`, giải mã bằng `Codable` với kiểu `Int64`. Cấm `JSONSerialization` hoặc `Double` trung gian.
- Thời gian lưu bằng `Int64` mili giây từ 1970 (không dùng chuỗi ngày).
- ID là chuỗi UUID viết hoa. Quan hệ lưu bằng ID, giá trị rỗng là `null`.
- Checksum = SHA-256 của `payload` được mã hóa theo dạng chuẩn: `sortedKeys`, không khoảng trắng thừa. Khi kiểm tra: giải mã payload, mã hóa lại đúng dạng chuẩn, băm, so sánh.
- Checksum bản rõ chỉ phát hiện hỏng file vô tình. Phong bì mã hóa dùng AES-GCM/AAD để phát hiện sửa dữ liệu/header.
- Có một "file mẫu vàng" cố định trong thư mục test. Test phải xác minh checksum của file này luôn đạt. Đổi dạng chuẩn thì phải tăng `schemaVersion`.

### Thuật toán export
1. Đọc dữ liệu, tính `expectedBalances` bằng `BalanceCalculator`.
2. Mã hóa, ghi ra file tạm cùng thư mục.
3. Đọc lại file tạm, kiểm tra checksum, số lượng và số dư khớp.
4. Đạt thì đổi tên thành file chính thức. Không đạt thì xóa file tạm, báo lỗi, không đụng tới các bản cũ.

### Thuật toán restore (thay thế toàn bộ)
1. Kiểm tra file: `format`, `schemaVersion` được hỗ trợ, checksum, số lượng khớp `summary`.
2. Kiểm tra cấu trúc: ID không trùng, mọi `walletId`/`toWalletId`/`categoryId` tồn tại, `amount > 0`, `kind` hợp lệ, quy tắc giao dịch như `TransactionValidator` (chuyển tiền có hai ví khác nhau và không có danh mục; thu/chi có ví và danh mục; loại danh mục khớp loại giao dịch).
3. Hiện tóm tắt (số ví, danh mục, giao dịch, tổng số dư, khoảng ngày) và chờ xác nhận.
4. Tạo bản `PreRestore` của dữ liệu hiện tại và kiểm tra bản đó đọc lại được. Không tạo được thì **dừng**.
5. Dùng `ModelContext` riêng, tắt autosave. Xóa giao dịch trước, rồi ví và danh mục, nạp dữ liệu từ file, **tính lại số dư từng ví và so với `expectedBalances` trước khi save**. Lệch hoặc lỗi bất kỳ thì `rollback`, dữ liệu cũ còn nguyên.
6. Save một lần. Xóa các ID "gần nhất" trong UserDefaults. Đặt `didSeedDefaults = true`.

### Quản lý bản backup
- `Backups/`: giữ 10 bản Auto/Manual gần nhất. `Backups/PreRestore/`: giữ 5 bản, **không** bị đẩy ra bởi bản Auto.
- Auto-backup bỏ qua nếu checksum trùng bản mới nhất (dữ liệu không đổi). Auto-backup bỏ qua nếu dữ liệu hiện **rỗng** mà bản trước có dữ liệu (chống ghi đè bản tốt bằng bản trống).
- Kích hoạt: khi app vào nền (dùng `beginBackgroundTask`) và sau mỗi 20 thay đổi giao dịch (thêm, sửa, xóa).
- Thư mục `Documents` hiện trong Tệp. Kiểm tra store SwiftData **không** nằm trong `Documents`.

### Nhắc nhở
- Theo dõi hai mốc: "backup gần nhất" và "chép ra ngoài gần nhất" (cập nhật khi Share Sheet báo đã hoàn tất).
- Thông báo cục bộ: mỗi lần chép ra ngoài thì hủy lịch cũ và đặt lại thông báo ở +14, +21, +24, +27 ngày rồi dừng. Nội dung chung chung, không có số tiền.
- Banner: vàng khi quá 7 ngày, đỏ khi quá 14 ngày, tính trên mốc "chép ra ngoài".

## 16. Quy tắc Cài đặt và khóa ứng dụng (Bước 5c, 6)

### Tab Cài đặt (tab thứ 5)
- Mục "Sao lưu": banner trạng thái, nút "Sao lưu ngay", "Chia sẻ bản mới nhất", "Danh sách bản sao lưu", "Khôi phục từ file", ghi chú nhắc bật iCloud Backup.
- Mục "Bảo mật": công tắc "Khóa bằng Face ID".
- Đã thêm Kiểm tra dữ liệu, Xuất CSV, tình trạng backup và Mã hóa bản sao lưu. Chưa có giao diện tùy biến.

### Khóa ứng dụng
- Dùng `LocalAuthentication`, chính sách `.deviceOwnerAuthentication` (sinh trắc học, tự rơi về mật mã máy).
- Khóa khi mở app từ trạng thái tắt, và khi quay lại từ nền sau hơn 30 giây.
- Khi bị khóa: **không dựng** nội dung thật (không chỉ phủ lớp lên), ẩn khỏi VoiceOver.
- Khi app không ở trạng thái active: phủ màn che để app switcher không lộ số liệu. Phủ màn che ≠ khóa. Hộp thoại Face ID của hệ thống cũng làm app "inactive", **không được** vì thế mà khóa lại hoặc lặp vòng xác thực.
- Bật công tắc: phải xác thực thành công trước. Tắt công tắc: cũng phải xác thực. Máy chưa đặt mật mã thì không bật được và có giải thích.
- Mặc định tắt trong code, nhưng bật là bắt buộc trong checklist nghiệm thu bước 7.
- Backup tự động chạy nền không phụ thuộc trạng thái khóa.
- Logic khóa (đếm thời gian, chuyển trạng thái) tách riêng và test được bằng đồng hồ giả và trình xác thực giả.
