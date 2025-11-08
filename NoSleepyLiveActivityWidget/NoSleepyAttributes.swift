//
//  NoSleepyAttributes.swift
//  NoSleepy
//
//  Created by Sahar Levy on 08/11/2025.
//

import ActivityKit
import Foundation

struct NoSleepAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var secondsRemaining: Int
        var progress: Double
    }

    // static attributes
    var title: String
}

