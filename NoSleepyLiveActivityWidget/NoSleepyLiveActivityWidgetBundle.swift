//
//  NoSleepyLiveActivityWidgetBundle.swift
//  NoSleepyLiveActivityWidget
//
//  Created by Sahar Levy on 08/11/2025.
//

import WidgetKit
import SwiftUI

@main
struct NoSleepyLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoSleepyLiveActivityWidget()
        // NoSleepyLiveActivityWidgetControl() // Removed - not needed and causes AppIntents training errors
        NoSleepyLiveActivityWidgetLiveActivity()
    }
}
