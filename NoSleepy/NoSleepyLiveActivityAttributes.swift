import Foundation
import ActivityKit

struct NoSleepyLiveActivityWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isMonitoring: Bool
        var isSleepDetected: Bool
        var monitoringStartTime: Date?
        var statusMessage: String
    }

    var title: String = "NoSleepy"
}




