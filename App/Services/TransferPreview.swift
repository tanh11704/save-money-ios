import Foundation

struct TransferPreview: Equatable {
    let sourceBefore: Int64, sourceAfter: Int64
    let destinationBefore: Int64, destinationAfter: Int64
    var sourceGoesNegative: Bool { sourceAfter < 0 }
    enum PreviewError: LocalizedError {
        case invalidSelection, missingBalance, overflow
        var errorDescription: String? {
            switch self {
            case .invalidSelection: return "Chọn hai ví khác nhau và số tiền hợp lệ."
            case .missingBalance: return "Chưa tính được số dư ví."
            case .overflow: return "Số dư sau chuyển vượt giới hạn tính toán."
            }
        }
    }
    /// `fee` leaves the source wallet too but does not reach the destination.
    static func make(amount: Int64, fee: Int64 = 0, source: Wallet, destination: Wallet, balances: [UUID: Int64]) throws -> TransferPreview {
        guard source.id != destination.id, (1...MoneyFormatter.maximumInput).contains(amount),
              (0...MoneyFormatter.maximumInput).contains(fee) else { throw PreviewError.invalidSelection }
        guard let sourceBefore = balances[source.id], let destinationBefore = balances[destination.id] else { throw PreviewError.missingBalance }
        let (afterAmount, amountUnderflow) = sourceBefore.subtractingReportingOverflow(amount)
        let (sourceAfter, feeUnderflow) = afterAmount.subtractingReportingOverflow(fee)
        let underflow = amountUnderflow || feeUnderflow
        let (destinationAfter, overflow) = destinationBefore.addingReportingOverflow(amount)
        guard !underflow && !overflow else { throw PreviewError.overflow }
        return Self(sourceBefore: sourceBefore, sourceAfter: sourceAfter, destinationBefore: destinationBefore, destinationAfter: destinationAfter)
    }
}
