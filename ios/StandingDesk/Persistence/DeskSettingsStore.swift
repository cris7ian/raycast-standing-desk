import Combine
import Foundation

struct StoredDeskSettings: Codable, Equatable {
    var selectedDeskID: UUID?
    var selectedDeskName: String?
    var selectionGeneration: UUID?
    var safetyAcknowledged = false
    var configuration = DeskConfiguration.default
    var sitHeight = DeskConfiguration.defaultSitHeight
    var standHeight = DeskConfiguration.defaultStandHeight
    var usedDayCount = 0
    var lastUsedDayKey: String?
    var completedMovementCount = 0
    var reviewAskDecision: String?

    private enum CodingKeys: String, CodingKey {
        case selectedDeskID
        case selectedDeskName
        case selectionGeneration
        case acknowledgedGeneration
        case safetyAcknowledged
        case configuration
        case sitHeight
        case standHeight
        case usedDayCount
        case lastUsedDayKey
        case completedMovementCount
        case reviewAskDecision
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedDeskID = try? values.decodeIfPresent(UUID.self, forKey: .selectedDeskID)
        selectedDeskName = try? values.decodeIfPresent(String.self, forKey: .selectedDeskName)
        selectionGeneration = try? values.decodeIfPresent(UUID.self, forKey: .selectionGeneration)

        if let acknowledged = try? values.decodeIfPresent(Bool.self, forKey: .safetyAcknowledged) {
            safetyAcknowledged = acknowledged
        } else {
            // Before the global flag existed, a non-nil generation meant the checklist was accepted.
            safetyAcknowledged = (try? values.decodeIfPresent(UUID.self, forKey: .acknowledgedGeneration)) != nil
        }

        configuration = (try? values.decodeIfPresent(DeskConfiguration.self, forKey: .configuration)) ?? .default
        sitHeight = (try? values.decodeIfPresent(Double.self, forKey: .sitHeight)) ?? DeskConfiguration.defaultSitHeight
        standHeight = (try? values.decodeIfPresent(Double.self, forKey: .standHeight)) ?? DeskConfiguration.defaultStandHeight
        usedDayCount = (try? values.decodeIfPresent(Int.self, forKey: .usedDayCount)) ?? 0
        lastUsedDayKey = try? values.decodeIfPresent(String.self, forKey: .lastUsedDayKey)
        completedMovementCount = (try? values.decodeIfPresent(Int.self, forKey: .completedMovementCount)) ?? 0
        reviewAskDecision = try? values.decodeIfPresent(String.self, forKey: .reviewAskDecision)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(selectedDeskID, forKey: .selectedDeskID)
        try values.encodeIfPresent(selectedDeskName, forKey: .selectedDeskName)
        try values.encodeIfPresent(selectionGeneration, forKey: .selectionGeneration)
        try values.encode(safetyAcknowledged, forKey: .safetyAcknowledged)
        try values.encode(configuration, forKey: .configuration)
        try values.encode(sitHeight, forKey: .sitHeight)
        try values.encode(standHeight, forKey: .standHeight)
        try values.encode(usedDayCount, forKey: .usedDayCount)
        try values.encodeIfPresent(lastUsedDayKey, forKey: .lastUsedDayKey)
        try values.encode(completedMovementCount, forKey: .completedMovementCount)
        try values.encodeIfPresent(reviewAskDecision, forKey: .reviewAskDecision)
    }
}

enum ReviewPromptDecision: String {
    case accepted
    case declined
}

enum ReviewPromptPolicy {
    static let minimumUsedDayCount = 5
    static let minimumCompletedMovementCount = 10

    static func shouldAsk(
        usedDayCount: Int,
        completedMovementCount: Int,
        reviewAskDecision: String?
    ) -> Bool {
        guard reviewAskDecision == nil else { return false }
        return usedDayCount >= minimumUsedDayCount
            && completedMovementCount >= minimumCompletedMovementCount
    }

    static func dayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

enum DeskSettingsSaveOutcome: Equatable {
    case saved
    case failed(String)
}

struct DeskSettingsSaveResult: Identifiable, Equatable {
    let id = UUID()
    let outcome: DeskSettingsSaveOutcome
}

@MainActor
final class DeskSettingsStore: ObservableObject {
    static let storageKey = "standing-desk.settings.v1"
    static let safetyAcknowledgementKey = "standing-desk.safety-acknowledged.v1"

    @Published private(set) var settings: StoredDeskSettings
    @Published private(set) var lastSaveResult: DeskSettingsSaveResult?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let separatelyAcknowledged = defaults.bool(forKey: Self.safetyAcknowledgementKey)
        if let data = defaults.data(forKey: Self.storageKey),
           var decoded = try? JSONDecoder().decode(StoredDeskSettings.self, from: data)
        {
            let normalized = decoded.normalize()
            let promotedSeparateAcknowledgement = separatelyAcknowledged && !decoded.safetyAcknowledged
            if promotedSeparateAcknowledgement {
                decoded.safetyAcknowledged = true
            }
            settings = decoded

            if normalized || promotedSeparateAcknowledgement {
                persistLoadedSettings()
            }
        } else {
            var initial = StoredDeskSettings()
            initial.safetyAcknowledged = separatelyAcknowledged
            settings = initial
            if separatelyAcknowledged {
                persistLoadedSettings()
            }
        }

        if settings.safetyAcknowledged, !separatelyAcknowledged {
            defaults.set(true, forKey: Self.safetyAcknowledgementKey)
        }
    }

    var hasSelectedDesk: Bool { settings.selectedDeskID != nil }

    var hasAcknowledgedSafety: Bool { settings.safetyAcknowledged }

    func selectDesk(id: UUID, name: String) {
        if settings.selectedDeskID != id {
            settings.selectedDeskID = id
            settings.selectionGeneration = UUID()
        }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.selectedDeskName = normalizedName.isEmpty ? settings.configuration.deskName : normalizedName
        persist()
    }

    func acknowledgeSafety() {
        guard !settings.safetyAcknowledged else { return }
        settings.safetyAcknowledged = true
        defaults.set(true, forKey: Self.safetyAcknowledgementKey)
        persist()
    }

    func updateConfiguration(_ configuration: DeskConfiguration, sitHeight: Double, standHeight: Double) throws {
        let validatedConfiguration = try configuration.validated()
        let validatedSitHeight = try validatedConfiguration.validatedPersistedTarget(sitHeight)
        let validatedStandHeight = try validatedConfiguration.validatedPersistedTarget(standHeight)
        settings.configuration = validatedConfiguration
        settings.sitHeight = validatedSitHeight
        settings.standHeight = validatedStandHeight
        persist()
    }

    func forgetDesk() {
        settings.selectedDeskID = nil
        settings.selectedDeskName = nil
        settings.selectionGeneration = nil
        persist()
    }

    func restoreDefaults() {
        settings.configuration = .default
        settings.sitHeight = DeskConfiguration.defaultSitHeight
        settings.standHeight = DeskConfiguration.defaultStandHeight
        persist()
    }

    var shouldAskForReview: Bool {
        ReviewPromptPolicy.shouldAsk(
            usedDayCount: settings.usedDayCount,
            completedMovementCount: settings.completedMovementCount,
            reviewAskDecision: settings.reviewAskDecision
        )
    }

    func recordAppForegroundDay() {
        let todayKey = ReviewPromptPolicy.dayKey()
        guard settings.lastUsedDayKey != todayKey else { return }
        settings.usedDayCount += 1
        settings.lastUsedDayKey = todayKey
        persist()
    }

    func recordCompletedMovement() {
        settings.completedMovementCount += 1
        persist()
    }

    func recordReviewPromptDecision(_ decision: ReviewPromptDecision) {
        guard settings.reviewAskDecision == nil else { return }
        settings.reviewAskDecision = decision.rawValue
        persist()
    }

    func clearLastSaveResult() {
        lastSaveResult = nil
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.storageKey)
            lastSaveResult = DeskSettingsSaveResult(outcome: .saved)
        } catch {
            lastSaveResult = DeskSettingsSaveResult(outcome: .failed(error.localizedDescription))
        }
    }

    private func persistLoadedSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private extension StoredDeskSettings {
    @discardableResult
    mutating func normalize() -> Bool {
        let original = self

        if (try? configuration.validated()) == nil {
            configuration = .default
        }

        if configuration.fallbackPersistedTarget(preferred: DeskConfiguration.defaultSitHeight) == nil {
            configuration = .default
        }

        sitHeight = normalizedTarget(sitHeight, fallback: DeskConfiguration.defaultSitHeight)
            ?? DeskConfiguration.defaultSitHeight
        standHeight = normalizedTarget(standHeight, fallback: DeskConfiguration.defaultStandHeight)
            ?? DeskConfiguration.defaultStandHeight

        if selectedDeskID == nil {
            selectedDeskName = nil
            selectionGeneration = nil
        } else {
            if selectionGeneration == nil {
                selectionGeneration = UUID()
            }
            if selectedDeskName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                selectedDeskName = configuration.deskName
            }
        }

        return self != original
    }

    func normalizedTarget(_ target: Double, fallback: Double) -> Double? {
        if let target = try? configuration.validatedPersistedTarget(target) {
            return target
        }
        return configuration.fallbackPersistedTarget(preferred: fallback)
    }
}

private extension DeskConfiguration {
    func validatedPersistedTarget(_ height: Double) throws -> Double {
        let normalized = try validatedTarget(height)
        guard normalized >= minimumHeight, normalized <= maximumHeight else {
            throw DeskConfigurationError.targetOutsideRange(
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight
            )
        }
        return normalized
    }

    func fallbackPersistedTarget(preferred: Double) -> Double? {
        let clamped = min(max(preferred, minimumHeight), maximumHeight)
        let lowestTenth = (minimumHeight * 10).rounded(.up) / 10
        let highestTenth = (maximumHeight * 10).rounded(.down) / 10

        for candidate in [clamped, lowestTenth, highestTenth] {
            if let normalized = try? validatedPersistedTarget(candidate) {
                return normalized
            }
        }
        return nil
    }
}
