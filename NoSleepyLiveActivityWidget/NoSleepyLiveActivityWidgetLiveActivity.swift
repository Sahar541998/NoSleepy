//
//  NoSleepyLiveActivityWidgetLiveActivity.swift
//  NoSleepyLiveActivityWidget
//
//  Created by Sahar Levy on 08/11/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NoSleepyLiveActivityWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var isMonitoring: Bool
        var isSleepDetected: Bool
        var monitoringStartTime: Date?
        var statusMessage: String
    }

    // Fixed non-changing properties about your activity go here!
    var title: String = "NoSleepy"
}

struct NoSleepyLiveActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoSleepyLiveActivityWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            HStack(spacing: 12) {
                Text(context.state.isSleepDetected ? "😡" : "🕵️")
                    .font(.largeTitle)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.isSleepDetected ? "⚠️ Sleep Detected - Alarm!" : "👁️ NoSleepy Watching")
                        .font(.headline)
                        .foregroundStyle(context.state.isSleepDetected ? .red : .primary)

                    Text(context.state.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .activityBackgroundTint(context.state.isSleepDetected ? Color.red.opacity(0.15) : Color.teal.opacity(0.1))
            .activitySystemActionForegroundColor(context.state.isSleepDetected ? .red : .primary)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Text(context.state.isSleepDetected ? "😡" : "🕵️")
                            .font(.title)
                        Text("NoSleepy")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let startTime = context.state.monitoringStartTime, context.state.isMonitoring {
                        Text(startTime, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.isSleepDetected ? "⚠️ Sleep Detected - Alarm Active!" : "👁️ Watching for sleep...")
                            .font(.headline)
                            .foregroundStyle(context.state.isSleepDetected ? .red : .primary)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text(context.state.isSleepDetected ? "😡" : "🕵️")
                    .font(.title3)
            } compactTrailing: {
                if context.state.isSleepDetected {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
            } minimal: {
                Text(context.state.isSleepDetected ? "😡" : "🕵️")
                    .font(.caption)
            }
            .widgetURL(URL(string: "nosleepy://monitoring"))
            .keylineTint(context.state.isSleepDetected ? Color.red : Color.teal)
        }
    }
}

extension NoSleepyLiveActivityWidgetAttributes {
    fileprivate static var preview: NoSleepyLiveActivityWidgetAttributes {
        NoSleepyLiveActivityWidgetAttributes(title: "NoSleepy")
    }
}

extension NoSleepyLiveActivityWidgetAttributes.ContentState {
    fileprivate static var monitoring: NoSleepyLiveActivityWidgetAttributes.ContentState {
        NoSleepyLiveActivityWidgetAttributes.ContentState(
            isMonitoring: true,
            isSleepDetected: false,
            monitoringStartTime: Date().addingTimeInterval(-3600), // 1 hour ago
            statusMessage: "Watching for drowsiness patterns..."
        )
    }
     
    fileprivate static var sleepDetected: NoSleepyLiveActivityWidgetAttributes.ContentState {
        NoSleepyLiveActivityWidgetAttributes.ContentState(
            isMonitoring: true,
            isSleepDetected: true,
            monitoringStartTime: Date().addingTimeInterval(-7200), // 2 hours ago
            statusMessage: "Wake up! Sleep signature detected."
        )
    }
}

#Preview("Notification", as: .content, using: NoSleepyLiveActivityWidgetAttributes.preview) {
   NoSleepyLiveActivityWidgetLiveActivity()
} contentStates: {
    NoSleepyLiveActivityWidgetAttributes.ContentState.monitoring
    NoSleepyLiveActivityWidgetAttributes.ContentState.sleepDetected
}
