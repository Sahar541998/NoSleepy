//
//  NoSleepyLiveActivityAttributes.swift
//  NoSleepy
//
//  Created by GPT-5 Codex on 08/11/2025.
//

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




