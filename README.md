# SaveMoney

Ứng dụng iPhone cá nhân, SwiftUI + SwiftData, theo [SPEC.md](SPEC.md).

## Trạng thái

Đã triển khai bước 1–4: giao dịch, ví/danh mục và thống kê tháng.
**Kết quả mới nhất:** 64/64 unit test model/service chạy đạt trên macOS bằng
Xcode 27.2; app build iOS Simulator đạt. Chưa chạy trên simulator/iPhone vì
chưa cài runtime iOS Simulator; smoke test iOS và kiểm tra trực quan còn chờ.

Các ghi nhận thiếu Xcode/SwiftDataMacros ở bước 1–3 bên dưới là lịch sử trước
khi có Xcode. Terminal vẫn trỏ vào Command Line Tools; dùng DEVELOPER_DIR như
hướng dẫn bên dưới để chạy bằng Xcode mà không đổi cấu hình máy.

Bước 5–7 (backup/restore, khóa app và nghiệm thu) chưa triển khai.

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
- [x] Build app cho iOS Simulator đạt (chưa chạy app).
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
Bootstrap này và test tương ứng đã được thay bằng DefaultDataSeeder ở bước 3.
Các test lựa chọn form vẫn được giữ và bổ sung kiểm tra archive.

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

- [ ] Chạy `Cmd+U` toàn bộ 65 test hiện tại trong scheme SaveMoney, sau đó `Cmd+B`.
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


## Bước 3a–3e — Ví và danh mục

### Schema và lần chạy đầu

**Trước khi chạy bản bước 3, xóa app SaveMoney khỏi simulator và iPhone rồi cài
lại.** Chủ dự án xác nhận chưa có dữ liệu thật và cho phép reset riêng lần này.
`Wallet.kindRaw` được thêm với mặc định `cash`; các giá trị gồm `cash`, `bank`,
`card`, `other`. Không có code tự xóa hoặc thay store khi mở app.

Máy hiện không có Xcode/simctl nên agent chưa gỡ app trên bất kỳ thiết bị nào.
Khi có Xcode, simulator đang boot có thể gỡ bằng:

```sh
xcrun simctl uninstall booted vn.tanh11704.SaveMoney
```

Trên iPhone: xóa ứng dụng SaveMoney bằng màn hình chính/Cài đặt trước lần cài
mới. Việc này xóa cả dữ liệu thử nghiệm và UserDefaults trong app. Đây không phải
kế hoạch migration cho dữ liệu thật. **Mọi thay đổi schema sau bước này phải xuất
backup trước, có kế hoạch migration và thử trên bản sao.**

Đã bỏ hoàn toàn TemporarySampleData và cờ tạo mẫu bước 2 khỏi code. Seeder mới
chỉ tạo khi chưa có `didSeedDefaults` và kho ví/danh mục/giao dịch trống. Tạo một
ví Tiền mặt số dư 0, 8 danh mục Chi và 2 danh mục Thu đúng SPEC; save xong mới bật
cờ. Store đã có dữ liệu không được trộn dữ liệu mặc định. Archive không làm mất
cờ và không kích hoạt seed lại.

### Services

- WalletService: tạo/sửa, trim/NFC tên, tối đa 30 ký tự, chống trùng không phân
  biệt hoa thường kể cả archive, chặn archive ví hoạt động cuối cùng, khôi phục.
- CategoryService: tên duy nhất trong cùng loại kể cả archive; loại Chi/Thu;
  không đổi loại khi có giao dịch; vẫn được sửa tên/icon, archive và khôi phục.
- Mỗi thao tác dùng context riêng, một lần save; lỗi rollback, không ảnh hưởng
  draft/context của màn hình khác. Không có API xóa thật ví hoặc danh mục.
- Sửa số dư ban đầu xem trước số dư trước/sau bằng BalanceCalculator; preview
  không sửa model. Khoản nợ vẫn dùng Int64, dấu âm do service áp dụng.
- Tổng số dư ở mọi tab gồm ví archive; số dư 0 không làm thay đổi tổng. Mục
  “Đã lưu trữ” vẫn chứa ví số dư 0 để có thể khôi phục chúng.

### Giao diện và kết nối

Tab thứ 3 “Ví”: tổng số dư, danh sách đang dùng, mục thu gọn “Đã lưu trữ”, nút
thêm và lối vào Quản lý danh mục. Sheet ví có tên/loại/số dư ban đầu, bàn phím số
và “Đang nợ”; nếu sửa số dư ban đầu của ví có giao dịch thì hiện cảnh báo và
số dư trước/sau. Archive luôn có xác nhận nêu số dư còn lại; khôi phục một chạm.

Danh mục chia Chi/Thu/Đã lưu trữ, sheet dùng lại cho thêm/sửa, 30 SF Symbols với
nhãn tiếng Việt, khóa Loại khi đã dùng. Lỗi xuất hiện bằng chữ đỏ, không qua
alert. Màn hình dùng màu hệ thống, Dynamic Type, nhãn VoiceOver, vùng chạm 44pt.
Chưa xác minh trực quan trên simulator hoặc iPhone.

Sau quản lý, cả ba tab tải lại snapshot. Form Thêm bỏ lựa chọn vừa archive mà
không xóa số tiền/ngày/ghi chú đang nhập; form sửa giữ được tham chiếu archive
của giao dịch cũ. UserDefaults gần nhất được lọc theo dữ liệu đang dùng. Không
có ví hoạt động thì hiện hướng dẫn sang tab Ví để thêm/khôi phục.

### Test mới và kiểm tra cuối

Test in-memory mới/bổ sung: tên trùng hoa thường/Unicode và mục archive, trim,
0/30/31 ký tự; archive ví cuối cùng; đổi loại danh mục đã dùng; archive/restore
giữ giao dịch và số dư; preview và sửa số dư ban đầu; lỗi cập nhật không thay
dữ liệu; seed chính xác một lần và không lặp sau archive; form bỏ chọn archive
nhưng vẫn giữ tham chiếu khi sửa. Bộ test bước 1 và các test còn áp dụng của
bước 2 được giữ; test bootstrap tạm được thay bằng test dữ liệu mặc định.

Kết quả lượt kiểm tra tổng hợp duy nhất ngày 10/11/2026:

- Parse toàn bộ Swift, plist/project, shared scheme và `git diff --check`: đạt.
- Source Xcode khớp filesystem: 27 file app, 10 file test, không thiếu/trùng.
- Có 50 test (49 unit test model/service + 1 smoke test app).
- 39 kiểm tra Foundation biên dịch từ mã nguồn thật MoneyFormatter, LocalCalendar
  và ManagementValidation: đạt, gồm tên tiếng Việt, Unicode, trim và độ dài.
- `swift test` toàn bộ bước 1–3: exit 1 ở biên dịch vì thiếu SwiftDataMacros;
  chưa thực thi các unit test. Log: `/tmp/savemoney-step3-test.log`.
- `swift build`: exit 1 cùng nguyên nhân. Log: `/tmp/savemoney-step3-build.log`.
- Build iOS bằng `xcodebuild`: exit 1 vì chỉ có Command Line Tools, chưa cài
  Xcode. Log: `/tmp/savemoney-step3-ios-build.log`.
- Chưa gỡ/cài app trên thiết bị; chưa kiểm tra trực quan, VoiceOver hoặc Dynamic
  Type trên iPhone. Không xem việc có code/test là xác nhận test đã đạt.

### Checklist chạy lại bước 3

- [ ] Xóa app thử nghiệm cũ khỏi simulator/iPhone trước khi cài schema mới.
- [ ] Chạy toàn bộ unit test, build iOS và chạy trên iPhone.
- [ ] Lần đầu đúng 1 ví/10 danh mục, đóng/mở lại và archive danh mục không seed lại.
- [ ] Thêm/sửa tên, kiểm tra trùng với mục archive, 30/31 ký tự và khoảng trắng.
- [ ] Thêm ví nợ, sửa số dư ban đầu: số dư trước/sau khớp BalanceCalculator.
- [ ] Archive ví còn tiền: tổng không đổi; ví cuối cùng bị chặn; khôi phục đúng.
- [ ] Danh mục có giao dịch khóa loại; đổi tên/icon cập nhật lịch sử; archive và
      khôi phục giữ giao dịch và số dư.
- [ ] Chọn ví/danh mục ở Thêm rồi archive ở tab Ví: lựa chọn cũ bị bỏ, draft còn.
      Sửa lịch sử cũ vẫn đọc được ví/danh mục archive.
- [ ] Dynamic Type lớn nhất, chế độ tối, VoiceOver: dùng được toàn bộ màn hình mới.


## Bước 4a–4d — Thống kê tháng

### Cách tính và giao diện

StatsService nhận năm/tháng (hoặc ReportingMonth), dùng LocalCalendar tại
Asia/Saigon. Khoảng tháng gồm đầu tháng và loại trừ đầu tháng sau. Tái sử dụng
BalanceCalculator.flowTotals cho cả tổng và danh mục thu/chi; không cộng tiền
lần nữa trong View. Giữ Int64, phát hiện tràn số. Chuyển tiền không xuất hiện
trong thu/chi/danh mục. Không lọc archive.

Giao dịch thiếu danh mục được gom riêng theo loại vào “Không có danh mục”. Chế
độ đọc của màn hình cho phép thiếu danh mục để người dùng vẫn vào được app và
sửa dữ liệu; validator tạo/sửa và calculator ở chế độ mặc định vẫn nghiêm ngặt.
Không sửa schema hoặc tự thay dữ liệu.

Danh mục sắp theo số tiền giảm dần, giữ ID riêng, chỉ hiện tổng dương. Phần trăm
được tính bằng Decimal rồi làm tròn tới một chữ số thập phân và lưu thành số
nguyên phần mười phần trăm để hiển thị; không dùng Double/Float, không suy ngược
phần trăm thành tiền. Chênh lệch có dấu +/−, số 0 hiển thị +0.

Tab thứ 4 “Thống kê”: tháng trước/sau (không vượt tháng hiện tại), chạm nhãn để
chọn tháng/năm, “Tháng này”, tóm tắt thu/chi/chênh lệch, chi và thu theo danh mục.
Chạm dòng mở sheet chỉ đọc, có tổng và giao dịch nhóm theo ngày, dùng lại
TransactionRow của Lịch sử. Không có biểu đồ, so sánh tháng, CSV hoặc lọc ví.

Dữ liệu lấy bằng @Query, báo cáo tính từ kết quả query chứ không cache. Sau mỗi
save, query dùng lại context đọc mới của store; chỉ report con được tái tạo,
state tháng và danh mục đang xem giữ ở cha. Query chi tiết cũng được làm mới.
Bố cục số liệu xếp dọc, không lineLimit cho tiền; màu hệ thống, VoiceOver có
loại/số tiền/phần trăm và nút chính có vùng chạm 44pt. Các kiểm tra này mới được
rà code/build, chưa xác nhận trực quan trên thiết bị.

### Kết quả test/build

- **64/64 unit test đạt**, gồm toàn bộ test còn áp dụng của bước 1–3 và 15 test
  Stats mới, SwiftData in-memory trên macOS. Không bỏ qua test nào trong package.
- App và test target iOS Simulator đều **BUILD SUCCEEDED** bằng Xcode 27.2,
  SDK iOS 27.2. Test target đã biên dịch đủ cả smoke test.
- Sửa trùng tên Category giữa model và Objective-C trong test bằng typealias
  có module rõ ràng; không đổi model hay schema.
- Project có 65 test khai báo (64 unit + 1 smoke test app); smoke test chưa chạy
  trên iOS. Danh sách simulator/runtime rỗng, không có iPhone được sử dụng.
- Log unit test: `/tmp/savemoney-step4-tests.log`.
- Log build app: `/tmp/savemoney-step4-ios-build.log`.
- Log build test target: `/tmp/savemoney-step4-test-target-build.log`.

Lệnh tái hiện (không cần đổi xcode-select):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --scratch-path /tmp/savemoney-xcode-swift-build
xcodebuild -project SaveMoney.xcodeproj -scheme SaveMoney -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/savemoney-step4-derived CODE_SIGNING_ALLOWED=NO build
```

### Đối chiếu cộng tay (chưa đối chiếu màn hình)

Chỉ nhập dữ liệu mẫu vào kho thử nghiệm trong tháng đang xem. Không tự seed các
giao dịch này vào app. Bảng dưới và các tổng được tính tay độc lập trước khi
so với StatsService trong test; chưa thay thế yêu cầu ghi ra giấy và so màn hình.

| Loại | Danh mục / hướng chuyển | Số tiền |
| --- | --- | ---: |
| Chi | Ăn uống | 120.000 |
| Chi | Ăn uống | 80.000 |
| Chi | Đi lại | 50.000 |
| Chi | Đi lại | 50.000 |
| Chi | Mua sắm | 200.000 |
| Chi | Mua sắm | 100.000 |
| Thu | Lương | 1.000.000 |
| Thu | Thu khác | 200.000 |
| Chuyển | Tiền mặt → Ngân hàng | 300.000 |
| Chuyển | Ngân hàng → Tiền mặt | 100.000 |

Cộng tay: Ăn uống 120.000 + 80.000 = **200.000**; Đi lại 50.000 + 50.000 =
**100.000**; Mua sắm 200.000 + 100.000 = **300.000**. Tổng chi **600.000**.
Thu 1.000.000 + 200.000 = **1.200.000**. Chênh lệch **+600.000**.

Màn hình cần hiện chi theo thứ tự: Mua sắm **300.000 (50,0%)**, Ăn uống
**200.000 (33,3%)**, Đi lại **100.000 (16,7%)**; tổng phần trăm **100,0%**.
Thu: Lương **1.000.000 (83,3%)**, Thu khác **200.000 (16,7%)**. Hai chuyển tiền
không đổi bất kỳ tổng thu/chi/danh mục nào. Mỗi dòng chi mở đúng 2 giao dịch,
mỗi dòng thu mở đúng 1 giao dịch. Test mẫu đã khớp các số cố định này.

### Nghiệm thu còn lại

- [x] Toàn bộ 64 unit test bước 1–4a đạt trên macOS, gồm ranh giới tháng, tháng
      nhuận, archive, thiếu danh mục, tổng khớp, phần trăm và tràn Int64.
- [x] Build app iOS đạt.
- [ ] Cài runtime iOS Simulator (Xcode → Settings → Components) hoặc chọn iPhone.
- [ ] Chạy smoke test/app trên iOS và nhập đúng 10 giao dịch mẫu trong tháng này.
- [ ] Ghi tổng ra giấy, đối chiếu từng số và tổng/phần trăm với màn hình.
- [ ] Thử 23:59 cuối tháng, 00:00 và 00:01 tháng sau, archive danh mục đã dùng.
- [ ] Thử tháng trống, chỉ thu/chỉ chi/chỉ chuyển; không tiến quá tháng hiện tại.
- [ ] Sửa/xóa ở Lịch sử, quay lại Thống kê và sheet chi tiết: cập nhật đúng.
- [ ] Dynamic Type lớn nhất, chế độ tối, VoiceOver, vùng chạm trên iPhone.
- [ ] Chạy trên iPhone thật.

**Bước 4 chưa qua toàn bộ cổng nghiệm thu Phần C** cho tới khi các ô còn lại
được kiểm tra trên màn hình và thiết bị. Chưa nhập dữ liệu thật trước backup.
