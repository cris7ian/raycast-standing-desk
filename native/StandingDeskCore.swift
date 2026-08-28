import CoreBluetooth
import Foundation

public enum DeskProtocol {
    public static var controlServiceUUID: CBUUID {
        CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
    }

    public static var controlCharacteristicUUID: CBUUID {
        CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")
    }

    public static var outputServiceUUID: CBUUID {
        CBUUID(string: "99FA0020-338A-1024-8A49-009C0215F78A")
    }

    public static var outputCharacteristicUUID: CBUUID {
        CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")
    }

    public static var inputServiceUUID: CBUUID {
        CBUUID(string: "99FA0030-338A-1024-8A49-009C0215F78A")
    }

    public static var inputCharacteristicUUID: CBUUID {
        CBUUID(string: "99FA0031-338A-1024-8A49-009C0215F78A")
    }

    public static let moveDownPayload = Data([0x46, 0x00])
    public static let moveUpPayload = Data([0x47, 0x00])
    public static let wakePayload = Data([0xfe, 0x00])
    public static let stopPayload = Data([0xff, 0x00])

    public static let targetWriteInterval: TimeInterval = 0.4
    public static let movementSetupDelay: TimeInterval = 0.2
    public static let movementTimeout: TimeInterval = 45
    public static let targetToleranceCm = 0.25
    public static let stableTargetReadingsRequired = 2
    public static let stallGracePeriod: TimeInterval = 2
    public static let stationaryHeightToleranceCm = 0.01
    public static let stationarySpeedTolerance = 0.01
    public static let stationaryReadingsBeforeStall = 5
}

public struct DeskReading: Equatable, Sendable {
    public let heightCm: Double
    public let speed: Double

    public init(heightCm: Double, speed: Double) {
        self.heightCm = heightCm
        self.speed = speed
    }
}

public struct DeskConfiguration: Codable, Equatable, Sendable {
    public static let defaultSitHeight = 70.0
    public static let defaultStandHeight = 110.0
    public static let `default` = DeskConfiguration(
        deskName: "Desk",
        baseHeight: 62,
        minimumHeight: 62,
        maximumHeight: 127,
        stepHeight: 1
    )

    public var deskName: String
    public var baseHeight: Double
    public var minimumHeight: Double
    public var maximumHeight: Double
    public var stepHeight: Double

    public init(
        deskName: String,
        baseHeight: Double,
        minimumHeight: Double,
        maximumHeight: Double,
        stepHeight: Double
    ) {
        self.deskName = deskName
        self.baseHeight = baseHeight
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
        self.stepHeight = stepHeight
    }

    @discardableResult
    public func validated() throws -> DeskConfiguration {
        guard !deskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeskConfigurationError.emptyDeskName
        }
        guard baseHeight.isFinite else { throw DeskConfigurationError.notFinite("Base Height") }
        guard minimumHeight.isFinite else { throw DeskConfigurationError.notFinite("Minimum Height") }
        guard maximumHeight.isFinite else { throw DeskConfigurationError.notFinite("Maximum Height") }
        guard stepHeight.isFinite else { throw DeskConfigurationError.notFinite("Raise and Lower Step") }
        guard baseHeight > 0, minimumHeight > 0, maximumHeight > 0 else {
            throw DeskConfigurationError.nonPositiveHeight
        }
        guard minimumHeight < maximumHeight else {
            throw DeskConfigurationError.invalidHeightRange
        }
        guard baseHeight <= minimumHeight else {
            throw DeskConfigurationError.baseExceedsMinimum
        }
        guard stepHeight > 0, stepHeight <= 20 else {
            throw DeskConfigurationError.invalidStepHeight
        }
        return self
    }

    public func validatedTarget(_ height: Double) throws -> Double {
        guard height.isFinite else { throw DeskConfigurationError.invalidTarget }
        guard height >= minimumHeight, height <= maximumHeight else {
            throw DeskConfigurationError.targetOutsideRange(minimumHeight: minimumHeight, maximumHeight: maximumHeight)
        }
        let normalized = (height * 10).rounded() / 10
        guard normalized >= minimumHeight, normalized <= maximumHeight else {
            throw DeskConfigurationError.targetOutsideRange(minimumHeight: minimumHeight, maximumHeight: maximumHeight)
        }
        return normalized
    }
}

public enum DeskConfigurationError: LocalizedError, Equatable, Sendable {
    case emptyDeskName
    case notFinite(String)
    case nonPositiveHeight
    case invalidHeightRange
    case baseExceedsMinimum
    case invalidStepHeight
    case invalidTarget
    case targetOutsideRange(minimumHeight: Double, maximumHeight: Double)

    public var errorDescription: String? {
        switch self {
        case .emptyDeskName:
            "Desk Bluetooth Name cannot be empty."
        case let .notFinite(label):
            "\(label) must be a number."
        case .nonPositiveHeight:
            "Base, Minimum, and Maximum Height must be above 0 cm."
        case .invalidHeightRange:
            "Minimum Height must be lower than Maximum Height."
        case .baseExceedsMinimum:
            "Base Height cannot exceed Minimum Height."
        case .invalidStepHeight:
            "Raise and Lower Step must be between 0 and 20 cm."
        case .invalidTarget:
            "Target height must be a number."
        case let .targetOutsideRange(minimumHeight, maximumHeight):
            "Target height must be between \(minimumHeight) and \(maximumHeight) cm."
        }
    }
}

public func rawTarget(for heightCm: Double, baseHeight: Double) -> UInt16? {
    let raw = ((heightCm - baseHeight) * 100).rounded()
    guard raw >= 0, raw <= Double(UInt16.max) else { return nil }
    return UInt16(raw)
}

public func decodeReading(_ data: Data, baseHeight: Double) -> DeskReading? {
    guard data.count >= 4 else { return nil }
    let rawHeight = UInt16(data[0]) | UInt16(data[1]) << 8
    let rawSpeedBits = UInt16(data[2]) | UInt16(data[3]) << 8
    let rawSpeed = Int16(bitPattern: rawSpeedBits)
    return DeskReading(
        heightCm: baseHeight + Double(rawHeight) / 100,
        speed: Double(rawSpeed) / 100
    )
}

public func littleEndianData(_ value: UInt16) -> Data {
    Data([UInt8(value & 0x00ff), UInt8((value & 0xff00) >> 8)])
}

public func isDiscoveryCandidate(
    peripheralName: String?,
    advertisedName: String?,
    advertisedServices: [CBUUID],
    nameFilter: String
) -> Bool {
    if [peripheralName, advertisedName]
        .compactMap({ $0 })
        .contains(where: { $0.localizedCaseInsensitiveContains(nameFilter) })
    {
        return true
    }
    return advertisedServices.contains(DeskProtocol.controlServiceUUID)
}

public func nudgedTarget(
    currentHeight: Double,
    delta: Double,
    minimumHeight: Double,
    maximumHeight: Double
) -> Double? {
    let proposed = currentHeight + delta
    let clamped = min(max(proposed, minimumHeight), maximumHeight)
    if delta > 0, clamped < currentHeight { return nil }
    if delta < 0, clamped > currentHeight { return nil }
    return clamped
}

public enum DeskMovementEvaluation: Equatable, Sendable {
    case moving
    case reached
    case stalled
}

public struct DeskMovementEvaluator: Sendable {
    public let targetHeight: Double
    private var stableTargetReadings = 0
    private var stationaryReadings = 0

    public init(targetHeight: Double) {
        self.targetHeight = targetHeight
    }

    public mutating func evaluate(
        _ reading: DeskReading,
        previous: DeskReading?,
        elapsed: TimeInterval
    ) -> DeskMovementEvaluation {
        if abs(reading.heightCm - targetHeight) <= DeskProtocol.targetToleranceCm {
            stableTargetReadings += 1
        } else {
            stableTargetReadings = 0
        }
        if stableTargetReadings >= DeskProtocol.stableTargetReadingsRequired {
            return .reached
        }

        if let previous,
           abs(previous.heightCm - reading.heightCm) < DeskProtocol.stationaryHeightToleranceCm,
           abs(reading.speed) < DeskProtocol.stationarySpeedTolerance,
           elapsed > DeskProtocol.stallGracePeriod
        {
            stationaryReadings += 1
        } else {
            stationaryReadings = 0
        }
        if stationaryReadings >= DeskProtocol.stationaryReadingsBeforeStall {
            return .stalled
        }
        return .moving
    }
}
