import Foundation

enum ManagementError: LocalizedError, Equatable {
    case emptyName, nameTooLong, duplicateName, invalidKind, invalidIcon, invalidOpeningBalance
    case lastActiveWallet, categoryInUse, missingRecord

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Hãy nhập tên."
        case .nameTooLong: return "Tên tối đa 30 ký tự."
        case .duplicateName: return "Tên đã tồn tại, kể cả trong mục đã lưu trữ."
        case .invalidKind: return "Loại đã chọn không hợp lệ."
        case .invalidIcon: return "Hãy chọn một biểu tượng trong danh sách."
        case .invalidOpeningBalance: return "Số dư ban đầu tối đa là 999.999.999.999 đồng hoặc khoản nợ tương ứng."
        case .lastActiveWallet: return "Phải còn ít nhất một ví đang dùng. Hãy thêm hoặc khôi phục ví khác trước."
        case .categoryInUse: return "Danh mục đã có giao dịch, không thể đổi loại. Hãy tạo danh mục mới."
        case .missingRecord: return "Dữ liệu không còn tồn tại. Hãy tải lại và thử lại."
        }
    }
}

struct ManagementValidation {
    static func name(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw ManagementError.emptyName }
        guard name.count <= 30 else { throw ManagementError.nameTooLong }
        return name
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            .compare(rhs.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping,
                     options: .caseInsensitive, locale: Locale(identifier: "vi_VN")) == .orderedSame
    }
}

