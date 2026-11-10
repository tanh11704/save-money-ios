import Foundation

struct TransactionDraft {
    var amount: Int64 = 0
    var kind: TransactionKind = .expense
    var date: Date = Date()
    var note: String = ""
    var wallet: Wallet?
    var toWallet: Wallet?
    var category: Category?

    func changingKind(to kind: TransactionKind) -> TransactionDraft {
        var draft = self
        draft.kind = kind
        if kind == .transfer { draft.category = nil }
        else {
            draft.toWallet = nil
            if draft.category?.kindRaw != kind.rawValue { draft.category = nil }
        }
        return draft
    }

    var normalized: TransactionDraft {
        var draft = self
        if kind == .transfer { draft.category = nil }
        else { draft.toWallet = nil }
        return draft
    }
}

struct TransactionValidator {
    enum ValidationError: String, LocalizedError, CaseIterable {
        case invalidAmount, amountTooLarge, missingWallet, missingCategory
        case missingDestination, sameWallet, unexpectedCategory, unexpectedDestination
        case categoryKindMismatch, archivedWallet, archivedDestination, archivedCategory

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "Số tiền phải lớn hơn 0 đồng."
            case .amountTooLarge: return "Số tiền tối đa là 999.999.999.999 đồng."
            case .missingWallet: return "Hãy chọn ví."
            case .missingCategory: return "Hãy chọn danh mục."
            case .missingDestination: return "Hãy chọn ví nhận tiền."
            case .sameWallet: return "Ví nguồn và ví nhận phải khác nhau."
            case .unexpectedCategory: return "Chuyển tiền không có danh mục."
            case .unexpectedDestination: return "Khoản thu hoặc chi không có ví nhận."
            case .categoryKindMismatch: return "Danh mục không phù hợp với loại giao dịch."
            case .archivedWallet: return "Không thể chọn mới ví đã lưu trữ."
            case .archivedDestination: return "Không thể chọn mới ví nhận đã lưu trữ."
            case .archivedCategory: return "Không thể chọn mới danh mục đã lưu trữ."
            }
        }
    }

    /// Existing archived references can be kept in their original role when editing.
    static func validate(_ draft: TransactionDraft, editing original: Transaction? = nil) throws {
        guard draft.amount > 0 else { throw ValidationError.invalidAmount }
        guard draft.amount <= MoneyFormatter.maximumInput else { throw ValidationError.amountTooLarge }
        guard let wallet = draft.wallet else { throw ValidationError.missingWallet }
        if wallet.isArchived && wallet.id != original?.wallet?.id { throw ValidationError.archivedWallet }
        switch draft.kind {
        case .transfer:
            guard draft.category == nil else { throw ValidationError.unexpectedCategory }
            guard let destination = draft.toWallet else { throw ValidationError.missingDestination }
            guard destination.id != wallet.id else { throw ValidationError.sameWallet }
            if destination.isArchived && destination.id != original?.toWallet?.id { throw ValidationError.archivedDestination }
        case .income, .expense:
            guard draft.toWallet == nil else { throw ValidationError.unexpectedDestination }
            guard let category = draft.category else { throw ValidationError.missingCategory }
            guard category.kindRaw == draft.kind.rawValue else { throw ValidationError.categoryKindMismatch }
            if category.isArchived && category.id != original?.category?.id { throw ValidationError.archivedCategory }
        }
    }
}
