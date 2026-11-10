# SaveMoney

Ứng dụng iPhone cá nhân, SwiftUI + SwiftData, theo [SPEC.md](SPEC.md).

## Trạng thái

Đã chuẩn bị bước khởi tạo và viết phần code bước 1 theo yêu cầu tiếp tục của
chủ dự án. Có ba model SwiftData, model container, BalanceCalculator và 10 test
in-memory. Chưa xác nhận bước 1 đạt; chưa chuyển sang giao diện giao dịch.

Bundle ID đã chốt: `vn.tanh11704.SaveMoney`. Giữ cố định trước và sau khi dùng thật.
Deployment target tạm là iOS 17.0 (tối thiểu cho SwiftData); cần xác nhận phiên bản
iOS của iPhone trước khi chốt cấu hình phát hành.

## Mở và kiểm tra

1. Cài Xcode đầy đủ, mở một lần để hoàn tất cài SDK và iOS Simulator.
2. Mở `SaveMoney.xcodeproj`, chọn scheme `SaveMoney` và một iPhone Simulator.
3. Chạy Product → Test (`Cmd+U`), sau đó Product → Build (`Cmd+B`).
4. Với iPhone thật: chọn Apple ID/Team trong Signing & Capabilities, kết nối
   iPhone, chọn thiết bị rồi Run. Không nhập dữ liệu thật.
5. Bật Cài đặt → [tên] → iCloud → Sao lưu iCloud trên iPhone.

Nếu dùng terminal, chọn Xcode làm developer directory trước:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -list -project SaveMoney.xcodeproj
xcodebuild -showdestinations -project SaveMoney.xcodeproj -scheme SaveMoney
# Thay SIMULATOR_UDID bằng ID simulator có trong kết quả trên.
xcodebuild -project SaveMoney.xcodeproj -scheme SaveMoney -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
xcodebuild -project SaveMoney.xcodeproj -scheme SaveMoney -destination 'generic/platform=iOS Simulator' build
```

## Cổng hoàn thành bước khởi tạo

- [x] Project và test target đã được tạo.
- [x] Bật `UIFileSharingEnabled` và `LSSupportsOpeningDocumentsInPlace`.
- [ ] Build iOS đạt.
- [ ] Smoke test chạy đạt trên simulator hoặc thiết bị.
- [ ] App trống chạy trên iPhone thật.
- [ ] Chủ dự án xác nhận iCloud Backup đã bật.

Ngày 10/11/2026: máy chỉ có Command Line Tools; cả lệnh build và test dừng vì
`xcodebuild` yêu cầu Xcode. Kiểm tra cú pháp Swift và plist đạt nhưng không thay
thế việc build/test iOS. Chưa chuyển sang bước 1 theo cổng kiểm tra của plan.

Yêu cầu mới của chủ dự án trong plan là agent commit sau mỗi bước, thay cho
quy tắc 13 của SPEC. Commit khởi tạo chỉ lưu tiến độ, không xác nhận bước đã đạt.


## Bước 1: model và số dư

- `App/Models/`: Wallet, Category, Transaction; thuộc tính có mặc định hoặc optional.
- `App/Services/BalanceCalculator.swift`: tính từng ví, tổng ví, tổng thu/chi và
  chi theo danh mục; giữ ví/danh mục archive, loại chuyển tiền khỏi thu/chi.
- `App/Services/LocalCalendar.swift`: lịch Gregorian tại Asia/Saigon, khoảng
  tháng có điểm cuối loại trừ.
- `App/Tests/BalanceCalculatorTests.swift`: 10 test gồm SwiftData in-memory,
  chuyển tiền, archive, số lớn, tràn số, ranh giới tháng, năm nhuận, dữ liệu
  không hợp lệ và cập nhật sau sửa/xóa giao dịch.
- Phép cộng dùng Int64 và báo lỗi khi tràn số; dữ liệu giao dịch không hợp lệ
  gây lỗi thay vì bị bỏ qua khi tính số dư.

Đối chiếu tay dữ liệu mẫu: tiền mặt ban đầu 1.000.000 + thu 500.000 − chi
120.000 − chuyển 300.000 = **1.080.000đ**. Ngân hàng ban đầu 2.000.000 + nhận
300.000 − chi 80.000 = **2.220.000đ**. Tổng **3.300.000đ**, thu **500.000đ**,
chi **200.000đ**. Test chứa các kết quả mong đợi này; chưa chạy đạt.

Có thể chạy bộ test model/service bằng Swift Package trên macOS khi có Xcode
đầy đủ (không thay thế kiểm thử app iOS):

```sh
swift test
swift build
```

Kết quả kiểm tra ngày 10/11/2026:

- Parse cú pháp toàn bộ Swift: đạt.
- Plist/project và XML shared scheme: đạt.
- `swift test`: thất bại ở biên dịch, chưa chạy test. Command Line Tools thiếu
  plugin `SwiftDataMacros.PersistentModelMacro` cho `@Model`.
- `swift build`: cũng bị chặn bởi plugin macro này.
- Build/test iOS và chạy trên iPhone: vẫn cần Xcode đầy đủ và thiết bị.

Chưa tạo dữ liệu tài chính hoặc store trên thiết bị. Schema này là schema khởi
đầu; nếu đã cài và nhập dữ liệu ngoài phiên này, cần báo lại trước khi chạy.
Commit bước 1 lưu tiến độ chưa được xác minh, không đánh dấu cổng hoàn thành.


## Bước 2a: tầng Services (chưa có giao diện)

Đã viết 5 service theo mục 12 và thêm 19 unit test:

- `MoneyFormatter`: Int64 → dấu chấm hàng nghìn + `₫`, đọc chuỗi nhập hợp lệ;
  bàn phím giữ state Int64 với phím số, `000`, xóa lùi. Vượt
  999.999.999.999 thì giữ số cũ. Định dạng số dư âm hỗ trợ cả Int64.min.
- `TransactionValidator`: kiểm tra số tiền, quan hệ theo loại, danh mục đúng
  loại, archive; lỗi tiếng Việt. Sửa giao dịch cũ được giữ nguyên quan hệ đã
  archive nhưng không được chọn mới quan hệ archive khác.
- `TransactionService`: tạo/sửa/xóa và save tường minh; khi đổi loại xóa danh
  mục hoặc ví đích thừa. Context mới cho mỗi thao tác, kiểm tra lại ID đã lưu
  và archive trong store. Save lỗi thì rollback context của thao tác; không
  save/rollback các thay đổi đang nhập ở main context.
- `TransactionGrouping`: ngày Asia/Saigon, mới nhất trước, thứ tự ổn định khi
  cùng thời điểm; tiêu đề hôm nay/hôm qua và ngày vi_VN.
- `RecentSelectionStore`: lưu ID UserDefaults riêng theo thu/chi/chuyển, chỉ
  cập nhật từ service sau khi save thành công; lọc ID thiếu hoặc đã archive
  khi lấy lựa chọn cho giao dịch mới.

Không đổi schema, chưa có dữ liệu mẫu hoặc UI bước 2b–2e.

Kiểm tra ngày 10/11/2026:

- Parse cú pháp Swift và plist/project: đạt; mọi source đã vào đúng target.
- Biên dịch trực tiếp mã nguồn thật MoneyFormatter + LocalCalendar bằng
  swiftc và chạy 29 phép kiểm tra độc lập: đạt (format/parse các mốc yêu cầu,
  giới hạn bàn phím, số âm lớn và ngày/tháng Asia/Saigon).
- `swift test` và `swift build`: thất bại ở bước biên dịch vì thiếu plugin
  `SwiftDataMacros` trong Command Line Tools; các unit test chưa được thực thi.
- Cần Xcode đầy đủ để xác minh persistence, validator/model và toàn bộ test.
  Chưa đánh dấu 2a đạt và chưa chuyển sang 2b.
