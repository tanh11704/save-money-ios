# SaveMoney

Ứng dụng iPhone cá nhân, SwiftUI + SwiftData, theo [SPEC.md](SPEC.md).

## Trạng thái

Đã triển khai code bước 1 và toàn bộ bước 2a–2e: Services, tab Thêm, Lịch sử,
sửa/xóa và hỗ trợ khả năng tiếp cận. Có 35 unit test model/service và một smoke
test app. Chưa xác nhận build/test iOS hoặc chạy trên thiết bị.

Theo yêu cầu “cứ làm toàn bộ, tôi sẽ chạy lại sau”, không chờ cổng test để viết
các phần còn lại của bước 2. Các bước 3–7 trong SPEC chưa được triển khai.

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
thế việc build/test iOS. Các cổng kiểm tra vẫn để mở dù đã viết bước tiếp theo.

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

Bước 2a không đổi schema; UI và bootstrap tạm được bổ sung ở 2b–2e bên dưới.

Kiểm tra ngày 10/11/2026:

- Parse cú pháp Swift và plist/project: đạt; mọi source đã vào đúng target.
- Biên dịch trực tiếp mã nguồn thật MoneyFormatter + LocalCalendar bằng
  swiftc và chạy 29 phép kiểm tra độc lập: đạt (format/parse các mốc yêu cầu,
  giới hạn bàn phím, số âm lớn và ngày/tháng Asia/Saigon).
- `swift test` và `swift build`: thất bại ở bước biên dịch vì thiếu plugin
  `SwiftDataMacros` trong Command Line Tools; các unit test chưa được thực thi.
- Cần Xcode đầy đủ để xác minh persistence, validator/model và toàn bộ test.
  Chưa đánh dấu 2a đạt; đã triển khai tiếp UI theo yêu cầu mới.

## Tiến độ bước 2b–2e

Theo yêu cầu mới, tiếp tục triển khai dù môi trường chưa chạy được SwiftData.
Việc này bỏ cổng chờ build/test giữa các phần; không đánh dấu các kiểm thử đã đạt.

### 2b — Tab Thêm

Đã có form SwiftUI, bàn phím số 0–9/000/xóa lùi, số tiền Int64, chip danh mục/ví
và số dư, ngày Asia/Saigon, ghi chú thu gọn và lỗi tiếng Việt ngay dưới nút Lưu.
Lưu thành công giữ lựa chọn, xóa số tiền, rung nhẹ và thông báo “Đã lưu”.
App mở vào tab Thêm. Form dùng lại được cho sửa ở 2d.

Ví/danh mục tạm chỉ được tạo một lần khi store hoàn toàn trống, qua
`TemporarySampleData`; không tạo giao dịch, không trộn vào kho đang có dữ liệu.
Bước 3 phải bỏ bootstrap này. Thêm 6 unit test cho lựa chọn form và bootstrap.

Parse Swift và plist đạt. `swift test`/`swift build` vẫn bị chặn ở plugin
SwiftDataMacros. Chưa xác minh giao diện, haptic hoặc persistence trên iPhone.

### 2c — Lịch sử

Đã nối tab Lịch sử: nhóm ngày qua TransactionGrouping, mới nhất trước, tổng số
dư qua BalanceCalculator, dấu thu/chi rõ ràng và nội dung rỗng theo SPEC.
Có tải lại khi kéo danh sách và thông báo lỗi khi không đọc được dữ liệu.
Parse Swift/plist đạt; test/build vẫn bị chặn bởi SwiftDataMacros.

### 2d — Sửa và xóa

Chạm dòng giao dịch mở sheet dùng lại TransactionFormView; Hủy không ghi dữ
liệu. Vuốt Xóa hoặc dùng hành động VoiceOver đều phải xác nhận. Tạo/sửa/xóa
chỉ qua TransactionService, sau khi save tải lại cả số dư và lịch sử.
Khi sửa giữ ID, ngày/ghi chú; khi đổi loại xóa trường không còn phù hợp.
Parse Swift/plist đạt; test/build vẫn bị chặn bởi SwiftDataMacros.


### 2e — Rà soát khả năng tiếp cận

- Dùng màu/vật liệu hệ thống, không khóa chế độ sáng/tối.
- Phím số, nút Lưu, chip chọn, thao tác chính có vùng chạm tối thiểu 44pt.
- Text theo Dynamic Type; danh mục/ví chuyển thành một cột ở cỡ trợ năng.
  Bộ chọn loại dùng segmented ở cỡ thông thường và menu hệ thống ở cỡ trợ năng
  để các nhãn không bị cắt. Dòng lịch sử xếp dọc ở cỡ trợ năng.
- Số tiền dùng monospacedDigit, co theo chiều ngang; nhãn VoiceOver giữ đủ loại
  và số tiền. Xóa có hành động VoiceOver và luôn qua xác nhận.
- Khi nhập ghi chú bằng bàn phím hệ thống, bàn phím tiền được thu gọn thành nút
  “Xong ghi chú” để không che vùng nhập trên iPhone nhỏ.
- Thông báo lỗi tiếng Việt; lỗi save giữ nguyên draft. Nếu save thành công nhưng
  tải lại lỗi, không báo save thất bại để tránh người dùng lưu trùng.
- Trở lại foreground tải lại snapshot và tiêu đề ngày theo Asia/Saigon.

Đã parse cú pháp mọi file Swift, lint plist/project, kiểm tra tham chiếu toàn bộ
source (19 file app, 9 file test) và chạy riêng 30 phép kiểm tra Foundation: đạt. Đã thử test/build cho từng
phần 2b, 2c, 2d, 2e; đều dừng ở lỗi thiếu SwiftDataMacros. Không khẳng định unit
test, UI hoặc khả năng tiếp cận đã chạy đạt.

### Checklist chạy lại khi có Xcode/iPhone (chưa thực hiện)

- [ ] Chạy `Cmd+U` toàn bộ 36 test trong scheme SaveMoney, sau đó `Cmd+B`.
- [ ] Cài/run trên iPhone thật; app mở vào Thêm, dữ liệu tạm chỉ tạo một lần.
- [ ] Chi: nhập số → chọn danh mục → Lưu; số tiền xóa, loại/ví/danh mục giữ lại,
      có rung nhẹ/“Đã lưu”, không tự đổi tab. Kiểm tra mở lại app nhớ lựa chọn.
- [ ] Thu và chuyển: thử đầy đủ; nguồn/đích không trùng; tổng số dư không đổi
      khi chuyển; kiểm tra nhập `999.999.999.999` rồi bấm thêm số/000 bị bỏ qua.
- [ ] Lịch sử nhóm đúng tại 23:59/00:00 Asia/Saigon; trạng thái rỗng và dấu +/−.
- [ ] Sửa đủ các cặp đổi loại, đổi ví, ngày, ghi chú; số dư cập nhật đúng.
      Hủy sửa không lưu. Hủy xóa giữ nguyên; xác nhận xóa cập nhật số dư.
- [ ] Kiểm tra tham chiếu archive bằng dữ liệu test: giữ đúng lịch sử và sửa cũ,
      không xuất hiện như lựa chọn mới. Bước 3 sẽ bổ sung UI quản lý archive.
- [ ] iPhone nhỏ, Dynamic Type lớn nhất, chế độ tối: không cắt nội dung, cuộn được,
      bàn phím/nút Lưu với tới được; thử ghi chú khi bàn phím hệ thống đang mở.
- [ ] VoiceOver: đọc rõ loại/số tiền/lựa chọn; nhập tiền, sửa và xác nhận xóa được.

Chưa nhập dữ liệu thật trước khi hoàn tất backup/restore và checklist mục 9 SPEC.
