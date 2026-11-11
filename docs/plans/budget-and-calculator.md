# Plan: Hạn mức chi tiêu và bàn phím tính toán

Hai tính năng độc lập, làm theo thứ tự nào cũng được. Bàn phím tính toán **không đổi schema** nên có thể làm trước.
Quy trình như SPEC: mỗi bước code → chạy test → commit.

---

## A. Bàn phím tính toán (+ / −)

### Mục tiêu
Gõ `50.000 + 35.000 − 5.000` ngay trên bàn phím số, app tự tính ra `80.000 ₫` để lưu. Dùng khi gộp nhiều khoản (ví dụ hóa đơn chia nhiều món) hoặc trừ tiền giảm giá.

### Quy tắc
- Chỉ có cộng và trừ, tính từ trái sang phải, không có ngoặc, nhân hay chia.
- Mọi toán hạng là `Int64` và không vượt `MoneyFormatter.maximumInput`. Không dùng `Double`.
- Kết quả tạm thời được phép âm hoặc bằng 0 (ví dụ `5.000 − 8.000` khi đang gõ dở), nhưng **chỉ lưu được khi kết quả nằm trong 1…999.999.999.999**. Ngoài khoảng đó thì nút Lưu bị vô hiệu kèm dòng giải thích, giống validation hiện tại.
- Phép cộng, trừ phải kiểm tra tràn số (`addingReportingOverflow`). Nếu tràn thì bỏ qua lần bấm đó, không crash.
- Chuỗi hiển thị luôn sinh ra từ các `Int64`, không bao giờ parse ngược từ chuỗi (giữ đúng quy tắc mục 12 của SPEC).

### Bước A1. `AmountExpression` + unit test (`App/Services/AmountExpression.swift`)
Một struct thuần, không phụ thuộc SwiftUI:

```swift
struct AmountExpression: Equatable {
    enum Operator { case plus, minus }
    private(set) var terms: [(Operator, Int64)]   // toán hạng đã chốt, phần tử đầu luôn là .plus
    private(set) var current: Int64?              // toán hạng đang gõ, nil ngay sau khi bấm toán tử
    private(set) var pendingOperator: Operator?

    init(amount: Int64 = 0)                        // dùng khi sửa giao dịch: bắt đầu bằng số tiền cũ
    var result: Int64? { get }                     // nil nếu tràn số
    var hasOperator: Bool { get }                  // có hiện dòng biểu thức không
    var displayText: String { get }                // "50.000 + 35.000 − 5.000"
    mutating func apply(_ key: MoneyFormatter.Key)
}
```

Mở rộng `MoneyFormatter.Key`: thêm `.plus`, `.minus`, `.equals`, `.clear`. `MoneyFormatter.applying(_:to:)` cũ vẫn dùng để gõ chữ số cho `current`, còn với các phím mới thì trả về số tiền giữ nguyên (cần đổi `switch` vì enum có thêm case).

Hành vi từng phím:

| Phím | Hành vi |
|---|---|
| Chữ số, `000` | Gõ vào `current` qua `MoneyFormatter.applying`. Nếu `current == nil` thì bắt đầu từ 0. |
| `+` / `−` | Có `current` thì chốt nó vào `terms` với toán tử đang chờ, rồi đặt toán tử mới. Đang chờ toán tử rồi (bấm `+` liên tiếp) thì chỉ **thay** toán tử. Biểu thức rỗng (0) thì bỏ qua. |
| `=` | Gộp toàn bộ thành một toán hạng duy nhất bằng `result`. Kết quả âm hoặc tràn số thì bỏ qua lần bấm. |
| `⌫` | Có `current` khác 0 thì xóa một chữ số. `current` bằng 0 hoặc nil thì xóa toán tử chờ, rồi lấy lại toán hạng trước làm `current`. |
| `C` | Về 0. |

Test bắt buộc:
- Gõ số thường không có toán tử thì kết quả giống hệt `MoneyFormatter.applying` (không làm vỡ luồng 3 lần chạm).
- `50.000 + 35.000 − 5.000` cho ra `80.000`.
- Bấm `+` rồi `−` liên tiếp thì chỉ giữ `−`.
- `⌫` xóa lần lượt chữ số, rồi toán tử, rồi chữ số của toán hạng trước.
- `5.000 − 8.000` cho `result == -3000`, và `=` bị bỏ qua.
- `999.999.999.999 + 999.999.999.999` không tràn: tính được nhưng vượt max nên không lưu được.
- Toán hạng đơn lẻ vẫn bị chặn ở max như cũ.
- `init(amount:)` với số tiền cũ, `⌫` hoạt động đúng.
- `displayText` dùng `MoneyFormatter.string` cho từng toán hạng và dấu `−` (U+2212) giống phần còn lại của app.

### Bước A2. Bàn phím 4 cột (`MoneyKeypad.swift`)
```
 1    2    3    ⌫
 4    5    6    −
 7    8    9    +
000   0    C    =
```
- Thêm tham số `showsOperators: Bool = false`. Khi `false` thì giữ layout 3 cột như hiện tại, để `WalletFormView` (số dư ban đầu) không đổi.
- Cột toán tử dùng `.buttonStyle(.bordered)` với `.tint(.accentColor)` để phân biệt với chữ số. Chỉ dùng màu hệ thống.
- Nhãn VoiceOver: "Cộng", "Trừ", "Bằng", "Xóa hết", "Xóa một chữ số".
- Mỗi phím vẫn có vùng chạm tối thiểu 44pt. Bàn phím 4 cột vẫn cao 4 hàng như cũ, nên không chiếm thêm chiều cao.
- Accessibility identifier: `keypad.plus`, `keypad.minus`, `keypad.equals`, `keypad.clear`.

### Bước A3. Nối vào form giao dịch (`TransactionFormView.swift`)
- Thêm `@State private var expression: AmountExpression`. Khởi tạo bằng `AmountExpression(amount: original?.amount ?? 0)`.
- Mỗi lần bấm phím: `expression.apply(key)`, rồi đặt `draft.amount = expression.result ?? 0` (hoặc một giá trị chắc chắn không hợp lệ). `TransactionValidator` giữ nguyên, vẫn là nơi duy nhất quyết định có lưu được không.
- `amountDisplay`:
  - Khi `expression.hasOperator`: dòng nhỏ phía trên hiện `expression.displayText` (`.font(.title3)`, `.monospacedDigit()`, `.foregroundStyle(.secondary)`, `lineLimit(2)`), dòng lớn hiện `= 80.000 ₫`.
  - Khi không có toán tử: hiển thị như hiện tại.
  - Kết quả âm thì dòng lớn hiện `−3.000 ₫`, và dòng validation dưới nút Lưu báo "Số tiền phải lớn hơn 0".
- Khi bấm **Lưu** có toán tử đang chờ thì lưu luôn `result`, không bắt bấm `=` trước. Như vậy vẫn giữ được 3 lần chạm.
- Lưu xong giao dịch mới: `expression = AmountExpression()` cùng lúc với `draft.amount = 0`.
- Đổi loại Chi/Thu/Chuyển: giữ nguyên biểu thức.
- VoiceOver cho số tiền: đọc biểu thức và kết quả, ví dụ "Chi, 50.000 cộng 35.000, bằng 85.000 đồng".

### Bước A4. Cập nhật SPEC
Mục 12, phần "Ô nhập số tiền": thêm phím `+`, `−`, `=`, `C`, quy tắc kết quả phải nằm trong 1…max, và việc chỉ form giao dịch mới có toán tử.

### Kiểm tra tay
- Nhập nhanh `50000` → danh mục → Lưu: vẫn 3 lần chạm, không thấy khác biệt.
- `120.000 + 45.000 − 15.000`, Lưu: lịch sử hiện `150.000 ₫`.
- Sửa một giao dịch cũ `200.000`, bấm `+ 50.000`, lưu: thành `250.000`.
- Bật Dynamic Type cỡ lớn nhất: dòng biểu thức xuống dòng, không bị cắt.

---

## B. Hạn mức chi tiêu theo danh mục và hạn mức tổng

### Đã chốt
- Hạn mức **lặp mỗi tháng**. Người dùng sửa được: mỗi lần sửa tạo bản ghi mới có `startMonth` là tháng sửa, các tháng cũ giữ hạn mức cũ.
- Có **hạn mức tổng** của cả tháng, độc lập với hạn mức từng danh mục.
- Chỉ tính khoản chi. Chuyển tiền và thu nhập không bao giờ tính. Khoản chi thuộc danh mục đã lưu trữ vẫn tính.
- Cảnh báo ở mốc 80% và 100%, dùng thông báo cục bộ, mỗi mốc chỉ báo một lần mỗi tháng.

### Bước B1. `BudgetService` + test — **ĐÃ XONG**
- `App/Services/BudgetService.swift`: `BudgetRule` (struct giá trị, `scope` là `.total` hoặc `.category(UUID)`), `activeRule`, `progress`, `level`, `crossedThresholds`.
- `App/Tests/BudgetServiceTests.swift`: 15 test.
- Service nhận `[BudgetRule]` chứ không nhận model SwiftData, nên các bước sau chỉ cần map `Budget` sang `BudgetRule`.

### Bước B2. Model `Budget` + migration
**Trước khi làm: xuất backup dữ liệu thật trên máy.**

`App/Models/Budget.swift`:
```swift
@Model final class Budget {
    var id: UUID = UUID()
    var scopeRaw: String = "category"   // "total" | "category"
    var category: Category?             // nil khi scope là total
    var limit: Int64 = 0
    var startYear: Int = 0
    var startMonth: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
}
```
- Mọi thuộc tính có giá trị mặc định (quy tắc 8 của SPEC).
- Lưu `scopeRaw` thay vì suy ra "total" từ `category == nil`, để nếu quan hệ bị hỏng thì một hạn mức danh mục không biến thành hạn mức tổng.
- Thêm `var rule: BudgetRule?` để map sang service. Trả về nil nếu dữ liệu không hợp lệ: `limit <= 0`, tháng sai, hoặc scope là `category` mà thiếu `category`.
- Migration:
  - Tạo `SaveMoneySchemaV1` (Wallet, Category, Transaction) và `SaveMoneySchemaV2` (thêm Budget), cùng `SaveMoneyMigrationPlan` dùng `.lightweight` từ V1 lên V2. Thêm entity mới là migration nhẹ.
  - Sửa `SaveMoneyApp.init` dùng `ModelContainer(for:migrationPlan:configurations:)`.
  - Sửa mọi chỗ tạo `Schema([...])`: `grep -rn "Schema(\[" App` (app, các test fixture, `BackupRestorer` nếu có).
- Test: mở một store V1 có dữ liệu mẫu bằng schema V2, mọi ví, danh mục, giao dịch và số dư còn nguyên.
- Thử tay: cài bản mới đè lên bản cũ có dữ liệu mẫu (không xóa app), dữ liệu còn nguyên.

### Bước B3. `BudgetService` ghi dữ liệu
Thêm vào `App/Services/BudgetService.swift`, hoặc tách `BudgetPersistence` theo kiểu `ManagementPersistence`:
- `setLimit(_ limit: Int64, scope:, from month: ReportingMonth, context:)`:
  - Nếu đã có bản ghi cùng scope và **cùng** `startMonth` thì cập nhật `limit` của bản ghi đó, để sửa nhiều lần trong một tháng không sinh nhiều bản ghi.
  - Nếu chưa có thì tạo bản ghi mới.
- `turnOff(scope:, from month:, context:)`: tạo hoặc cập nhật bản ghi `isArchived = true` tại tháng đó.
- Kiểm tra `limit` trong 1…`MoneyFormatter.maximumInput`, và chỉ cho phép danh mục loại chi.
- Hạn mức tổng nhỏ hơn tổng các hạn mức danh mục: **cho phép** nhưng có cảnh báo ở UI, không chặn.
- Test: sửa hai lần trong cùng tháng ra một bản ghi, sửa sang tháng sau ra hai bản ghi, tắt rồi bật lại, từ chối danh mục thu.

### Bước B4. Backup `schemaVersion: 2`
`BackupFile.swift`, `BackupExporter.swift`, `BackupValidator.swift`, `BackupRestorer.swift`:
- `Payload` thêm `budgets: [BudgetRecord]` (id, scopeRaw, categoryID, limit, startYear, startMonth, isArchived, createdAt).
- `budgets` nằm trong phần được băm checksum.
- Khi đọc: file `schemaVersion == 1` không có `budgets` thì coi như rỗng, nên **vẫn khôi phục được**. File `schemaVersion > 2` bị từ chối.
- Validator: `categoryID` phải trỏ tới danh mục loại chi có trong file, `limit > 0`, tháng hợp lệ, scope `total` thì không có `categoryID`.
- Restore thay thế toàn bộ thì xóa cả `Budget` cũ trong cùng transaction.
- Tóm tắt trước khi khôi phục: thêm dòng "N hạn mức".
- Test:
  - Thêm `Fixtures/golden-v2.json`. **Giữ nguyên** `golden-v1.json` và test của nó.
  - Test vòng tròn có hạn mức (cả total lẫn category, cả bản ghi archived).
  - Khôi phục file v1 thì 0 hạn mức, dữ liệu khác khớp.
  - `budgets` trỏ tới danh mục không tồn tại thì bị từ chối và dữ liệu hiện tại không đổi.
  - Sửa một ký tự trong `budgets` thì checksum phát hiện.
- Cập nhật mục 8 của SPEC.

### Bước B5. UI quản lý hạn mức
- `App/Views/Budgets/BudgetListView.swift`: vào từ tab Ví, mục "Ngân sách", đặt cạnh "Quản lý danh mục" (không thêm tab mới).
  - Trên cùng: "Hạn mức tổng tháng này", số tiền hoặc "Chưa đặt".
  - Danh sách danh mục chi đang dùng, mỗi dòng: icon, tên, hạn mức hoặc "Chưa đặt".
  - Chạm một dòng để mở sheet.
- `App/Views/Budgets/BudgetFormView.swift` (sheet):
  - Nhập tiền bằng `MoneyKeypad` (không bật toán tử).
  - Ghi chú nhỏ "Áp dụng từ tháng 11/2026 và các tháng sau. Các tháng trước giữ hạn mức cũ."
  - Nút "Tắt hạn mức" có xác nhận.
  - Nếu tổng hạn mức danh mục lớn hơn hạn mức tổng thì hiện dòng cảnh báo, không chặn lưu.
- Danh mục đã lưu trữ không hiện ở danh sách đặt mới, nhưng hạn mức cũ của nó vẫn được tính trong thống kê.

### Bước B6. Hiển thị tiến độ
- **Tab Thống kê** (`StatsView.swift`), thêm section "Ngân sách" ngay dưới tổng thu/chi, theo tháng đang xem:
  - Mỗi dòng: tên, `ProgressView(value:)` (giá trị kẹp tối đa 1), dòng "1.250.000 / 2.000.000 ₫", "Còn 750.000 ₫" hoặc "Vượt 250.000 ₫".
  - Trạng thái **luôn có chữ**: "Sắp hết" (≥80%), "Đã vượt" (≥100%). Màu chỉ là phụ: `.orange` và `.red` hệ thống.
  - Tháng không có hạn mức nào thì ẩn section, hoặc hiện link "Đặt hạn mức".
- **Form Thêm giao dịch** (`TransactionFormView.swift`): chip danh mục chi có hạn mức hiện `subtitle` là "Còn 750.000 ₫" hoặc "Vượt 250.000 ₫". Tính trong `TransactionScreenStore` để View không chứa logic tiền (quy tắc 6).
- VoiceOver: "Ăn uống, đã chi 1.250.000 trên 2.000.000 đồng, còn 750.000 đồng".

### Bước B7. Cảnh báo 80% / 100%
- `App/Services/BudgetAlertService.swift`, gọi từ `TransactionScreenStore.save` **sau khi** lưu thành công:
  1. Lấy tháng của giao dịch (theo ngày giao dịch, không phải hôm nay).
  2. Tính `spent` trước và sau thay đổi cho scope danh mục đó và scope total.
  3. Gọi `BudgetService.crossedThresholds`.
  4. Với mỗi mốc vừa vượt, kiểm tra key `budget.alert.<scope>.<yyyyMM>.<80|100>` trong `UserDefaults`. Chưa có thì gửi thông báo ngay (`UNTimeIntervalNotificationTrigger` 1 giây) và ghi key.
- Sửa hoặc xóa giao dịch làm giảm số chi: không báo, và không xóa key. Như vậy dao động quanh mốc không gây báo lặp.
- Giao dịch nhập lùi về tháng cũ: vẫn tính đúng tháng đó. Có thể bỏ qua thông báo nếu không phải tháng hiện tại, tùy bạn.
- Quyền thông báo: dùng lại cơ chế của `ReminderService`. Không có quyền thì im lặng, không chặn lưu.
- Nội dung:
  - "Ăn uống đã dùng 80% hạn mức tháng 11 (1.600.000 / 2.000.000 ₫)"
  - "Đã vượt hạn mức tổng tháng 11: 5.200.000 / 5.000.000 ₫"
- Test (dùng `NotificationScheduling` giả như `BackupAutomationTests`):
  - Vượt 80% thì gửi một thông báo. Lưu thêm vẫn dưới 100% thì không gửi.
  - Một giao dịch nhảy từ 70% lên 120% thì gửi 2 thông báo.
  - Xóa giao dịch rồi lưu lại vượt mốc trong cùng tháng thì không gửi lại.
  - Sang tháng mới thì gửi lại được.
  - Chuyển tiền không bao giờ gây thông báo.
- Đưa vào SPEC: mục 6 đánh dấu đã làm phần ngân sách.

### Thứ tự gợi ý
A1 → A2 → A3 → A4 (không đổi schema, dùng được ngay) → **backup** → B2 → B3 → B4 → B5 → B6 → B7.
B4 (backup v2) phải xong trước khi nhập hạn mức thật, để hạn mức không bị mất khi khôi phục.
