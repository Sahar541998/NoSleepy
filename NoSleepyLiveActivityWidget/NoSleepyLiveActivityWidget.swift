import SwiftUI
import WidgetKit

private let openAppURL = URL(string: "nosleepy://monitoring")!

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
        let content = VStack(spacing: 12) {
            Text("🕵️")
                .font(.system(size: 44))
            Text("Start Monitoring")
                .font(.headline)
            Text("Open NoSleepy to enable the watcher.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link(destination: openAppURL) {
                Label("Open NoSleepy", systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()

        if #available(iOS 17.0, *) {
            content
                .containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
                .background(Color(.systemBackground))
        }
    }
}

public struct NoSleepyLiveActivityWidget: Widget {
    let kind: String = "NoSleepyLiveActivityWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonitoringProvider()) { entry in
            NoSleepyLiveActivityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NoSleepy Monitor")
        .description("A quick way to open NoSleepy and start monitoring.")
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

#Preview(as: .systemMedium) {
    NoSleepyLiveActivityWidget()
} timeline: {
    MonitoringWidgetEntry(date: Date())
}
