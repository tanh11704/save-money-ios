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
        case categoryKindMismatch, archivedWallet, archivedDestination, archivedCategory, personToPerson, incomeToPerson, adjustmentMisuse

        var errorDescription: String? {
            switch self {
            case .personToPerson: return "Không chuyển tiền giữa hai người. Chọn một ví của bạn."
            case .incomeToPerson: return "Ghi thu nợ trong Sổ nợ, không ghi thu nhập vào ví người."
            case .adjustmentMisuse: return "Ví điều chỉnh chỉ dùng để điều chỉnh số dư một ví của bạn."
            case .invalidAmount: return "Số tiền phải lớn hơn 0 đồng."
            case .amountTooLarge: return "Số tiền tối đa là 999.999.999.999 đồng."
            case .missingWallet: return "Chọn ví."
            case .missingCategory: return "Chọn danh mục."
            case .missingDestination: return "Chọn ví nhận tiền."
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
        if let error = validationErrors(draft, editing: original).first { throw error }
    }

    /// The integrity checker uses the same rules, while showing every defect.
    static func validationErrors(_ draft: TransactionDraft, editing original: Transaction? = nil) -> [ValidationError] {
        var errors: [ValidationError] = []
        if draft.amount <= 0 { errors.append(.invalidAmount) }
        if draft.amount > MoneyFormatter.maximumInput { errors.append(.amountTooLarge) }
        if let wallet = draft.wallet {
            if wallet.isArchived && wallet.id != original?.wallet?.id { errors.append(.archivedWallet) }
        } else { errors.append(.missingWallet) }
        if draft.kind == .income && draft.wallet?.isPerson == true { errors.append(.incomeToPerson) }
        if draft.kind == .transfer && draft.wallet?.isPerson == true && draft.toWallet?.isPerson == true { errors.append(.personToPerson) }
        // The adjustment wallet may only move money to or from one of the user's own wallets.
        let touchesAdjustment = draft.wallet?.isAdjustment == true || draft.toWallet?.isAdjustment == true
        if touchesAdjustment && (draft.kind != .transfer || draft.wallet?.isPerson == true || draft.toWallet?.isPerson == true) {
            errors.append(.adjustmentMisuse)
        }
        switch draft.kind {
        case .transfer:
            if draft.category != nil { errors.append(.unexpectedCategory) }
            if let destination = draft.toWallet {
                if destination.id == draft.wallet?.id { errors.append(.sameWallet) }
                if destination.isArchived && destination.id != original?.toWallet?.id { errors.append(.archivedDestination) }
            } else { errors.append(.missingDestination) }
        case .income, .expense:
            if draft.toWallet != nil { errors.append(.unexpectedDestination) }
            if let category = draft.category {
                if category.kindRaw != draft.kind.rawValue { errors.append(.categoryKindMismatch) }
                if category.isArchived && category.id != original?.category?.id { errors.append(.archivedCategory) }
            } else { errors.append(.missingCategory) }
        }
        return errors
    }
}
