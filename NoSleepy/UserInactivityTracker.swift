import Foundation
import UIKit

protocol UserInactivityTracking {
    func noteUserInteraction()
    func currentInactivityDuration() -> TimeInterval
}

final class UserInactivityTracker: UserInactivityTracking {
    private let lock = NSLock()
    private var lastInteractionDate: Date

    init() {
        // Start now to avoid marking the user as inactive immediately on launch
        self.lastInteractionDate = Date()
        // Refresh on app activation since user likely engaged with device
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.noteUserInteraction()
        }
    }

    func noteUserInteraction() {
        lock.lock()
        lastInteractionDate = Date()
        lock.unlock()
    }

    func currentInactivityDuration() -> TimeInterval {
        lock.lock()
        let last = lastInteractionDate
        lock.unlock()
        return Date().timeIntervalSince(last)
    }
}


