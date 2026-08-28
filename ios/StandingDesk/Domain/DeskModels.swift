import Foundation

struct DiscoveredDesk: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let isConnected: Bool
}

enum DeskConnectionState: Equatable {
    case bluetoothUnavailable(String)
    case disconnected
    case scanning
    case connecting
    case connected
    case moving(target: Double)
    case stopping

    var label: String {
        switch self {
        case let .bluetoothUnavailable(message): message
        case .disconnected: appString("Disconnected")
        case .scanning: appString("Scanning")
        case .connecting: appString("Connecting")
        case .connected: appString("Connected")
        case let .moving(target):
            appFormat(
                "Moving to %@ cm",
                target.formatted(.number.precision(.fractionLength(1)))
            )
        case .stopping: appString("Stopping")
        }
    }

    var isMoving: Bool {
        if case .moving = self { return true }
        return false
    }
}

enum PendingMovement: Equatable {
    case sit
    case stand
    case nudge(Double)
}
