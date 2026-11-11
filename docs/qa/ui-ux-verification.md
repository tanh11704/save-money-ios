# Kiểm tra UI/UX

## U1: màu và thành phần dùng chung

- Màu danh mục dùng FNV-1a 64 bit cho icon chưa biết, không dùng `hashValue`.
- Kiểm tra WCAG sRGB chữ trắng trên 10 màu danh mục: tỷ lệ tương phản 5,70–6,62:1, vượt 4,5:1. Hai appearance dùng cùng màu nền icon để duy trì tỷ lệ này.
- Màu nhấn và màu loại giao dịch có biến thể sáng/tối riêng. Nội dung và nền dùng màu ngữ nghĩa hệ thống.
- Hình trang trí ẩn với VoiceOver và cỡ chữ Accessibility. Thiếu asset thì vẫn hiện nhãn và SF Symbol.
- Preview thư viện có sáng, tối và AX5. Rà tương tác trên máy thật vẫn cần thiết.
