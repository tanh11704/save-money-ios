# SaveMoney

Ứng dụng iPhone cá nhân, SwiftUI + SwiftData, theo [SPEC.md](SPEC.md).

## Trạng thái

Đang ở bước khởi tạo. Đã chuẩn bị app trống, XCTest target và shared scheme.
Chưa tạo model hoặc chức năng của bước 1. SwiftData sẽ được cấu hình container
khi có ba model; không tạo schema giả ở bước khởi tạo.

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
