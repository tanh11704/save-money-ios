import SwiftUI
import WidgetKit

// K0 feasibility probe only. No store, App Group, balance or transaction data.
struct TrialEntry: TimelineEntry { let date: Date }
struct TrialProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrialEntry { TrialEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (TrialEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TrialEntry>) -> Void) {
        completion(Timeline(entries: [TrialEntry(date: Date())], policy: .never))
    }
}
@main
struct SaveMoneyWidgetTrial: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SaveMoneyWidgetTrial", provider: TrialProvider()) { _ in
            VStack(spacing: 8) {
                Image(systemName: "plus.circle").font(.largeTitle)
                Text("SaveMoney").font(.headline)
                Text("Bản thử K0").font(.caption)
            }
            .widgetURL(URL(string: "savemoney://add?kind=expense"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SaveMoney — thử SideStore")
        .description("Chỉ thử cài và làm mới chữ ký. Không đọc dữ liệu.")
        .supportedFamilies([.systemSmall])
    }
}
