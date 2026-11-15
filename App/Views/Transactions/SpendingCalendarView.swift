import SwiftUI

/// Month grid where each day is shaded by how much was spent; tapping a day filters the list.
/// Follows the payday cycle, so a 25/10–24/11 cycle shows those days, Monday first.
struct SpendingCalendarView: View {
    let transactions: [Transaction]
    @Binding var month: ReportingMonth
    @Binding var selectedDay: Date?
    let current: ReportingMonth
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    private let weekdays = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    private var days: [Date] {
        let calendar = LocalCalendar.calendar
        return (0..<month.dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: month.interval.start) }
    }

    /// Blank cells before the first day so columns line up Monday…Sunday.
    private var leadingBlanks: Int {
        let weekday = LocalCalendar.calendar.component(.weekday, from: month.interval.start) // 1 = Sunday
        return (weekday + 5) % 7
    }

    var body: some View {
        let totals = SpendingHeatmap.dailyExpenses(transactions: transactions, in: month.interval)
        let maximum = totals.values.max() ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        VStack(spacing: Spacing.s) {
            HStack {
                Button { if let previous = month.previous { month = previous; selectedDay = nil } } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Tháng trước")
                Spacer()
                VStack(spacing: 0) {
                    Text(month.title).font(.headline).multilineTextAlignment(.center)
                    Text("Tổng chi \(MoneyFormatter.compact(totals.values.reduce(Int64(0)) { $0.addingReportingOverflow($1).partialValue }))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button { if let next = month.next(upTo: current) { month = next; selectedDay = nil } } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(month.next(upTo: current) == nil)
                .accessibilityLabel("Tháng sau")
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true) }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 1).accessibilityHidden(true) }
                ForEach(days, id: \.self) { day in cell(day, amount: totals[day] ?? 0, maximum: maximum) }
            }
            HStack(spacing: 4) {
                Text("Ít").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 3).fill(color(level)).frame(width: 14, height: 14) }
                Text("Nhiều").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if selectedDay != nil {
                    Button("Bỏ chọn ngày") { selectedDay = nil }.font(.caption).frame(minHeight: 44)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func color(_ level: Int) -> Color {
        let expense = Color("Expense")
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return expense.opacity(0.25)
        case 2: return expense.opacity(0.45)
        case 3: return expense.opacity(0.7)
        default: return expense
        }
    }

    private func cell(_ day: Date, amount: Int64, maximum: Int64) -> some View {
        let calendar = LocalCalendar.calendar
        let level = SpendingHeatmap.level(amount, maximum: maximum)
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        let future = day > Date()
        return Button {
            selectedDay = selected ? nil : day
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: day))").font(.caption.weight(isToday ? .bold : .regular)).monospacedDigit()
                if amount > 0 && !typeSize.isAccessibilitySize {
                    Text(MoneyFormatter.compact(amount)).font(.system(size: 8)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(level >= 3 ? Color.white : future ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(color(level), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : isToday ? Color.primary.opacity(0.5) : .clear,
                                                              lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(StatsPeriod.weekdayLabel(day)) \(StatsPeriod.dayMonth(day))")
        .accessibilityValue(amount > 0 ? "Chi " + MoneyFormatter.string(from: amount).replacingOccurrences(of: "₫", with: "đồng") : "Không chi")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Bỏ lọc ngày này" : "Lọc giao dịch của ngày này")
    }
}
