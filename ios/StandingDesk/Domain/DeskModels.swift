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
        case .disconnected: "Disconnected"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case let .moving(target): "Moving to \(target.formatted(.number.precision(.fractionLength(1)))) cm"
        case .stopping: "Stopping"
        }
    }

    var isMoving: Bool {
        if case .moving = self { return true }
        return false
    }
}

enum PendingMovement {
    case sit
    case stand
    case nudge(Double)
}
