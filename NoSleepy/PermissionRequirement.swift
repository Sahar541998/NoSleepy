import SwiftUI

enum PermissionStatus: Equatable {
    case pending
    case granted
    case denied

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }

    var systemImageName: String {
        switch self {
        case .pending:
            return "clock"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending:
            return Color.yellow
        case .granted:
            return Color.green
        case .denied:
            return Color.red
        }
    }
}


