import WidgetKit
import SwiftUI

/// Home-screen widget: check-in health + subscription due (reads App Group).
struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(
            date: Date(),
            headline: "签到 —/—",
            detail: "订阅 —",
            failed: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> StatusEntry {
        let d = UserDefaults(suiteName: "group.app.parsnip6345.lake8262") ?? .standard
        let healthy = d.integer(forKey: "widget.checkin.healthy")
        let total = d.integer(forKey: "widget.checkin.total")
        let failed = d.integer(forKey: "widget.checkin.failed")
        let due = d.integer(forKey: "widget.sub.due")
        let nextName = d.string(forKey: "widget.sub.nextName") ?? ""
        let nextDays = d.integer(forKey: "widget.sub.nextDays")
        let headline = d.string(forKey: "widget.headline")
            ?? (total > 0 ? "签到 \(healthy)/\(total)" : "XIN's Tool")
        var detail = due > 0 ? "\(due) 笔订阅 14 天内到期" : "订阅正常"
        if !nextName.isEmpty, nextDays >= 0 {
            detail = "\(nextName) · \(nextDays) 天"
        }
        return StatusEntry(date: Date(), headline: headline, detail: detail, failed: failed)
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let headline: String
    let detail: String
    let failed: Int
}

struct StatusWidgetEntryView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Color.accentColor)
                Text("XIN's Tool")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            Text(entry.headline)
                .font(family == .systemSmall ? .subheadline.weight(.bold) : .headline.weight(.bold))
                .minimumScaleFactor(0.8)
                .lineLimit(2)
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if entry.failed > 0 {
                Text("\(entry.failed) 项签到异常")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

@main
struct StatusWidget: Widget {
    let kind = "StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                StatusWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StatusWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(.systemBackground))
            }
        }
        .configurationDisplayName("状态摘要")
        .description("签到健康度与即将到期的订阅。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
