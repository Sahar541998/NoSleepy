import SwiftUI
import WidgetKit

struct MonitoringWidgetEntry: TimelineEntry {
    let date: Date
}

struct MonitoringProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonitoringWidgetEntry {
        MonitoringWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MonitoringWidgetEntry) -> ()) {
        completion(MonitoringWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonitoringWidgetEntry>) -> ()) {
        let entries = (0..<5).map { offset in
            MonitoringWidgetEntry(date: Calendar.current.date(byAdding: .hour, value: offset, to: Date()) ?? Date())
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NoSleepyLiveActivityWidgetEntryView: View {
    var entry: MonitoringWidgetEntry

    var body: some View {
        VStack(spacing: 12) {
            Text("🕵️")
                .font(.system(size: 44))
            Text("NoSleepy Monitor")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Keep NoSleepy open to stay awake.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemBackground))
    }
}

struct NoSleepyLiveActivityWidget: Widget {
    let kind: String = "NoSleepyLiveActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonitoringProvider()) { entry in
            NoSleepyLiveActivityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NoSleepy Monitor")
        .description("Glance at the NoSleepy monitoring status.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge]
        } else {
            return [.systemSmall, .systemMedium]
        }
    }
}

#Preview(as: .systemSmall) {
    NoSleepyLiveActivityWidget()
} timeline: {
    MonitoringWidgetEntry(date: .now)
}
