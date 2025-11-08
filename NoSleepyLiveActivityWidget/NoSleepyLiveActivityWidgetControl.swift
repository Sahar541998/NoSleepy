//
//  NoSleepyLiveActivityWidgetControl.swift
//  NoSleepyLiveActivityWidget
//
//  Created by Sahar Levy on 08/11/2025.
//

import Foundation

// Disabled - not needed for NoSleepy and causes AppIntents training errors
// struct NoSleepyLiveActivityWidgetControl: ControlWidget {
//     var body: some ControlWidgetConfiguration {
//         StaticControlConfiguration(
//             kind: "sahar.NoSleepy.NoSleepyLiveActivityWidget",
//             provider: Provider()
//         ) { value in
//             ControlWidgetToggle(
//                 "Start Timer",
//                 isOn: value,
//                 action: StartTimerIntent()
//             ) { isRunning in
//                 Label(isRunning ? "On" : "Off", systemImage: "timer")
//             }
//         }
//         .displayName("Timer")
//         .description("A an example control that runs a timer.")
//     }
// }

// extension NoSleepyLiveActivityWidgetControl {
//     struct Provider: ControlValueProvider {
//         var previewValue: Bool {
//             false
//         }
//
//         func currentValue() async throws -> Bool {
//             let isRunning = true // Check if the timer is running
//             return isRunning
//         }
//     }
// }

// Disabled - not needed for NoSleepy
// struct StartTimerIntent: SetValueIntent {
//     static let title: LocalizedStringResource = "Start a timer"
//
//     @Parameter(title: "Timer is running")
//     var value: Bool
//
//     func perform() async throws -> some IntentResult {
//         // Start / stop the timer based on `value`.
//         return .result()
//     }
// }
