# Kiểm tra UI/UX

## U1: màu và thành phần dùng chung

- Màu danh mục dùng FNV-1a 64 bit cho icon chưa biết, không dùng `hashValue`.
- Kiểm tra WCAG sRGB chữ trắng trên 10 màu danh mục: tỷ lệ tương phản 5,70–6,62:1, vượt 4,5:1. Hai appearance dùng cùng màu nền icon để duy trì tỷ lệ này.
- Màu nhấn và màu loại giao dịch có biến thể sáng/tối riêng. Nội dung và nền dùng màu ngữ nghĩa hệ thống.
- Hình trang trí ẩn với VoiceOver và cỡ chữ Accessibility. Thiếu asset thì vẫn hiện nhãn và SF Symbol.
- Preview thư viện có sáng, tối và AX5. Rà tương tác trên máy thật vẫn cần thiết.


## Kiểm tra tự động ngày 11/11/2026

| Phạm vi | Kết quả | Ghi chú |
|---|---|---|
| Core macOS | 194/194 | Gồm lịch sử, nợ, net worth, overflow và backup v1–v4 |
| Bộ iOS đầy đủ | 203/203 | Chạy trước lượt chỉnh tương phản và bố cục cuối |
| iOS bổ sung | 15/15 | Tương phản, màu asset, README trong bundle, các màn mới, 7 test nợ và 4 test so sánh tháng |
| Render và tương phản cuối | 2/2 | Đã xem ảnh sheet chuyển/nợ AX5, khôi phục hai cột và logo khóa |
| UI keyboard smoke | 4/4 | Ví, Danh mục, Định kỳ bấm Xong; Ví bấm Return; xác nhận bàn phím về 0 |

Các test UI dùng `--keyboard-smoke`, container chỉ trong RAM và tắt animation
trong fixture; không mở store hay bản sao lưu thật. Runner đầu tiên trên runtime
24B8117 bị kẹt khi nạp Accessibility. Runtime 24B91016s chạy được; helper đợi
bàn phím và thử focus lại một lần khi Simulator bỏ sự kiện focus lúc mở lạnh.
Lượt cuối cả 4 ca đều qua. Không coi đây là bằng chứng thao tác máy thật.

Bộ render gồm AX5 tối ở 375×667 và chữ nhỏ nhất sáng ở 430×932. Ảnh tĩnh
chỉ chứng minh viewport đã chụp, không chứng minh nội dung bên dưới có thể
cuộn/chạm hoặc VoiceOver đọc đúng. Các file xcresult nằm trong
`build/Calculator/Logs/Test/`; ảnh xuất ở `build/AccessibilityReview/`.

## Màu và ảnh

- Chữ trên nút: OnAccent trắng ở chế độ sáng, đen ở chế độ tối.
- Tương phản sRGB theo asset:

| Nền nút | Sáng | Tối |
|---|---:|---:|
| AccentColor | 4,82:1 | 11,98:1 |
| Income | 5,72:1 | 12,33:1 |
| Expense | 5,70:1 | 10,67:1 |
| Transfer | 6,43:1 | 11,70:1 |

- Test iOS xác minh màu thật trong bundle và chữ trắng trên cả 10 màu danh mục đạt ≥4,5:1 ở cả hai appearance.
- Đã rà contact sheet 18 hình trên nền sáng/tối: không chữ/số, cùng bảng màu,
  giữ alpha. Mỗi PNG trong app dưới 150.000 byte; lớn nhất 149.715 byte.
- Ba hình bổ sung và prompt ở `docs/qa/ui-illustrations.md`. Logo dùng lại AppIcon.

## Cần kiểm tra trên iPhone thật

- [ ] Mọi ô tên, ghi chú và mật khẩu: đóng bằng Return/Xong và kéo.
- [ ] Nhập tiền → chọn danh mục → Lưu; thử máy nhỏ và AX5, không cần tìm nút ẩn.
- [ ] Cuộn/chạm mọi nội dung, số tiền dài, biểu thức âm và Dynamic Type lớn nhất.
- [ ] VoiceOver: ô danh mục có lựa chọn, số dư trước/sau, Sổ nợ và các cảnh báo.
- [ ] Tăng độ tương phản, Giảm trong suốt và Giảm chuyển động ở Cài đặt iPhone.
- [ ] Chuyển Tất cả/đổi chiều, số dư cuối ngày và tổng thu/chi không đổi.
- [ ] Cho vay 500k, thu 200k, trả hộ 150k, trả vượt số nợ rồi khôi phục backup v4.
- [ ] Mã hóa/khôi phục, Keychain khi cài lại/ký lại và K0 SideStore refresh theo checklist giai đoạn 3.

Phí chuyển khoản U6.4 và hạn trả/nhắc nợ U7.6 là bước tùy chọn, chưa làm.
SwiftData vẫn V3; backup mới v4, golden-v1/v2/v3 giữ nguyên, thêm golden-v4.
K1 chưa làm và vẫn chờ kết quả K0 trên thiết bị.


Ảnh cuối: `build/AccessibilityReview/ui-final-signedoff/`, từ
`Test-SaveMoney-2026.11.11_15-05-16-+0700.xcresult`. Sau rà ảnh, huy hiệu ngày
cho phép xuống dòng và điều hướng được tạo lại sau restore để không giữ màn
chi tiết của ví/người thuộc bộ dữ liệu cũ.
