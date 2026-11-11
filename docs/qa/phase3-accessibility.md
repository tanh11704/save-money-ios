# Giai đoạn 3 — Rà giao diện và nghiệm thu thiết bị

Ngày: 11/11/2026. Chỉ dùng dữ liệu giả. File này ghi kết quả QA, không phải file plan.

## Phạm vi tự động

`AccessibilityRenderingTests` dựng ảnh 21 màn hình/vùng hiển thị ở hai cấu hình: 375×667 pt, AX5, tối; và 430×932 pt, chữ nhỏ nhất, sáng. Ảnh được giữ trong xcresult để rà trực quan. Đây là ảnh tĩnh của viewport đầu, **không** thay thế thao tác cuộn/chạm, VoiceOver hoặc thử trên máy thật.

| Màn hình | AX5 tối | Chữ nhỏ nhất sáng | Cuộn/chạm, VoiceOver, tương phản cao, giảm trong suốt |
|---|---|---|---|
| Thêm | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Lịch sử | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Sửa giao dịch | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Ví và form ví | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Danh mục và form danh mục | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Ngân sách và form | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Định kỳ và form | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Thống kê | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Biểu đồ ngày và vòng (ảnh riêng) | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Chi tiết danh mục | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Cài đặt | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Khôi phục | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Mã hóa | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Xuất CSV | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Kiểm tra toàn vẹn | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |
| Khóa app | Đã rà viewport đầu | Đã rà viewport đầu | Chưa nghiệm thu |

Ảnh trước sửa đã phát hiện phím 000 bị ellipsis, bàn phím định kỳ tràn ngang và tên danh mục trong trường một dòng bị cắt. Các lỗi đã được sửa và render lại. Một số tiêu đề điều hướng dài vẫn được hệ thống rút gọn ở AX5; tên danh mục và số tiền nằm trong nội dung riêng, xuống dòng đủ. Chưa xác nhận phần dưới màn hình khi cuộn hoặc khi mở bàn phím.

## Thay đổi phục vụ Trợ năng

- Biểu thức dài không giới hạn hai dòng ở cỡ Accessibility.
- Số tiền ở lịch sử được xuống dòng ở cỡ Accessibility.
- Biểu đồ ngày cao 260 pt, vòng cao 280 pt ở cỡ Accessibility; nhãn trục ngày còn 1, 10, 20, ngày cuối.
- Có preview AX5 tối và chữ nhỏ nhất sáng trong `AccessibilityPreview.swift`.
- Bàn phím số dùng lưới cột cố định, chữ phím tăng tối đa 32 pt và co để giữ đầy đủ 000, vùng chạm tối thiểu 44 pt. Ở cỡ Accessibility, form giao dịch/ví/hạn mức/định kỳ mở với bàn phím thu gọn; chạm số tiền để mở lại.
- Tên ví/danh mục/định kỳ được nhập nhiều dòng. Nhãn chu kỳ/ngày được tách khỏi điều khiển để tránh ép rộng form; ngày compact có giới hạn cỡ chữ riêng, nhãn ngoài vẫn theo AX5.
- Tổng chi đặt dưới vòng ở cỡ Accessibility để tránh cắt chuỗi số tiền trong lỗ vòng. Bộ chọn loại ví dùng tên chữ, tránh icon làm ép chiều rộng.
- Các nút mới có minHeight 44 pt, các trường dùng thành phần hệ thống.

## Bắt buộc trên iPhone thật trước khi dùng mã hóa với dữ liệu thật

- [ ] Ghi mật khẩu ra nơi an toàn ngoài iPhone; kiểm tra nhập lại được.
- [ ] Bật mã hóa, xem mọi file trong Backups/ và PreRestore/ không còn bản rõ.
- [ ] Chia sẻ file mã hóa ra iCloud Drive.
- [ ] Diễn tập xóa/cài lại và khôi phục bằng mật khẩu trên dữ liệu mẫu; đối chiếu số dư.
- [ ] Thử sai mật khẩu: dữ liệu không đổi.
- [ ] Đo PBKDF2 600.000 vòng trên máy thật (mục tiêu khoảng 0,3–1 giây).
- [ ] Tắt mã hóa: bản mới rõ, bản cũ vẫn mở bằng mật khẩu cũ.
- [ ] Thử 4 hành động Phím tắt qua Face ID; Siri tiếng Việt tùy ngôn ngữ hệ thống.
- [ ] Thử widget K0 qua SideStore, thêm vào màn hình chính và làm mới chữ ký; chỉ sau khi đạt mới làm K1.
