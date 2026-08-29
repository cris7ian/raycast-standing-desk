import XCTest
@testable import StandingDesk

final class DeskSettingsStoreTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DeskSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor func testSelectionAndAcknowledgementSurviveRelaunch() {
        let store = DeskSettingsStore(defaults: defaults)
        let deskID = UUID()
        store.selectDesk(id: deskID, name: "Desk")
        store.acknowledgeSafety()

        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.settings.selectedDeskID, deskID)
        XCTAssertEqual(relaunchedStore.settings.selectedDeskName, "Desk")
        XCTAssertTrue(relaunchedStore.hasAcknowledgedSafety)
    }

    @MainActor func testAcknowledgementRemainsAfterSettingsAndDeskChanges() throws {
        let store = DeskSettingsStore(defaults: defaults)
        store.selectDesk(id: UUID(), name: "Desk")
        store.acknowledgeSafety()

        var configuration = store.settings.configuration
        configuration.stepHeight = 2
        try store.updateConfiguration(
            configuration,
            sitHeight: store.settings.sitHeight,
            standHeight: store.settings.standHeight
        )

        store.restoreDefaults()
        store.selectDesk(id: UUID(), name: "Other Desk")
        store.forgetDesk()

        XCTAssertTrue(store.hasAcknowledgedSafety)
    }

    @MainActor func testSelectingSameDeskKeepsSelectionGeneration() {
        let store = DeskSettingsStore(defaults: defaults)
        let deskID = UUID()
        store.selectDesk(id: deskID, name: "Desk")
        let generation = store.settings.selectionGeneration

        store.selectDesk(id: deskID, name: "Renamed Desk")

        XCTAssertEqual(store.settings.selectionGeneration, generation)
        XCTAssertEqual(store.settings.selectedDeskName, "Renamed Desk")
    }

    @MainActor func testSelectingDeskWithBlankAdvertisementUsesConfigurationName() {
        let store = DeskSettingsStore(defaults: defaults)

        store.selectDesk(id: UUID(), name: "  \n")

        XCTAssertEqual(store.settings.selectedDeskName, DeskConfiguration.default.deskName)
    }

    @MainActor func testDecodesPartialSettingsWithoutDiscardingSelectedDesk() throws {
        let deskID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": deskID.uuidString,
            "selectedDeskName": "Desk",
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.selectedDeskID, deskID)
        XCTAssertEqual(store.settings.configuration, .default)
        XCTAssertNotNil(store.settings.selectionGeneration)
    }

    @MainActor func testGeneratedSelectionGenerationIsPersistedDuringMigration() throws {
        let deskID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": deskID.uuidString,
            "selectedDeskName": "Desk",
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let migratedStore = DeskSettingsStore(defaults: defaults)
        let migratedGeneration = try XCTUnwrap(migratedStore.settings.selectionGeneration)
        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.settings.selectionGeneration, migratedGeneration)
    }

    @MainActor func testMalformedSelectedDeskNameUsesConfigurationName() throws {
        let deskID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": deskID.uuidString,
            "selectedDeskName": 42,
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.selectedDeskID, deskID)
        XCTAssertEqual(store.settings.selectedDeskName, DeskConfiguration.default.deskName)
    }

    @MainActor func testMalformedConfigurationDoesNotDiscardSelectedDesk() throws {
        let deskID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": deskID.uuidString,
            "selectedDeskName": "Desk",
            "configuration": ["unexpected": true],
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.selectedDeskID, deskID)
        XCTAssertEqual(store.settings.configuration, .default)
    }

    @MainActor func testInvalidStoredConfigurationAndPresetsFallBackSafely() throws {
        let invalidConfiguration = DeskConfiguration(
            deskName: "Desk",
            baseHeight: 62,
            minimumHeight: 120,
            maximumHeight: 80,
            stepHeight: 1
        )
        var stored = StoredDeskSettings()
        stored.configuration = invalidConfiguration
        stored.sitHeight = 5
        stored.standHeight = 500
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.configuration, .default)
        XCTAssertEqual(store.settings.sitHeight, DeskConfiguration.defaultSitHeight)
        XCTAssertEqual(store.settings.standHeight, DeskConfiguration.defaultStandHeight)
    }

    @MainActor func testMigratesLegacyAcknowledgedGenerationToGlobalFlag() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": UUID().uuidString,
            "selectedDeskName": "Desk",
            "selectionGeneration": UUID().uuidString,
            "acknowledgedGeneration": UUID().uuidString,
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertTrue(store.hasAcknowledgedSafety)
    }

    @MainActor func testAcknowledgementSurvivesMalformedSettingsBlob() {
        let store = DeskSettingsStore(defaults: defaults)
        store.acknowledgeSafety()
        defaults.set(Data("not json".utf8), forKey: DeskSettingsStore.storageKey)

        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertTrue(relaunchedStore.hasAcknowledgedSafety)
    }

    @MainActor func testLegacyAcknowledgementIsCopiedToIndependentStorage() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": UUID().uuidString,
            "selectionGeneration": UUID().uuidString,
            "acknowledgedGeneration": UUID().uuidString,
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        _ = DeskSettingsStore(defaults: defaults)
        defaults.set(Data("not json".utf8), forKey: DeskSettingsStore.storageKey)
        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertTrue(relaunchedStore.hasAcknowledgedSafety)
    }

    @MainActor func testSuccessfulMutationPublishesSaveResult() {
        let store = DeskSettingsStore(defaults: defaults)

        store.selectDesk(id: UUID(), name: "Desk")
        let firstResultID = store.lastSaveResult?.id
        store.restoreDefaults()

        XCTAssertEqual(store.lastSaveResult?.outcome, .saved)
        XCTAssertNotEqual(store.lastSaveResult?.id, firstResultID)
        store.clearLastSaveResult()
        XCTAssertNil(store.lastSaveResult)
    }

    @MainActor func testRejectsPresetOutsideLimits() {
        let configuration = DeskConfiguration.default
        XCTAssertThrowsError(try configuration.validatedTarget(50))
    }

    @MainActor func testRejectsPresetWhoseRoundingCrossesConfiguredLimit() {
        let store = DeskSettingsStore(defaults: defaults)
        let original = store.settings
        let configuration = DeskConfiguration(
            deskName: "Desk",
            baseHeight: 62,
            minimumHeight: 62.04,
            maximumHeight: 127,
            stepHeight: 1
        )

        XCTAssertThrowsError(
            try store.updateConfiguration(
                configuration,
                sitHeight: 62.04,
                standHeight: 110
            )
        )
        XCTAssertEqual(store.settings, original)
    }

    @MainActor func testStoredRangeWithoutRepresentableTargetFallsBackSafely() throws {
        var stored = StoredDeskSettings()
        stored.configuration = DeskConfiguration(
            deskName: "Desk",
            baseHeight: 62,
            minimumHeight: 62.04,
            maximumHeight: 62.06,
            stepHeight: 1
        )
        stored.sitHeight = 62.04
        stored.standHeight = 62.06
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.configuration, .default)
        XCTAssertEqual(store.settings.sitHeight, 62.0)
        XCTAssertEqual(store.settings.standHeight, 62.1)
    }

    @MainActor func testStoredPresetsUseRepresentableTenthInsideCustomRange() throws {
        var stored = StoredDeskSettings()
        stored.configuration = DeskConfiguration(
            deskName: "Desk",
            baseHeight: 62,
            minimumHeight: 70.04,
            maximumHeight: 70.14,
            stepHeight: 1
        )
        stored.sitHeight = 70.04
        stored.standHeight = 70.14
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.configuration, stored.configuration)
        XCTAssertEqual(store.settings.sitHeight, 70.1)
        XCTAssertEqual(store.settings.standHeight, 70.1)
    }

    @MainActor func testReviewPromptPolicyDoesNotAskBeforeFiveUsedDays() {
        XCTAssertFalse(
            ReviewPromptPolicy.shouldAsk(
                usedDayCount: 4,
                completedMovementCount: 10,
                reviewAskDecision: nil
            )
        )
    }

    @MainActor func testReviewPromptPolicyDoesNotAskBeforeMovementThreshold() {
        XCTAssertFalse(
            ReviewPromptPolicy.shouldAsk(
                usedDayCount: 5,
                completedMovementCount: 9,
                reviewAskDecision: nil
            )
        )
    }

    @MainActor func testReviewPromptPolicyAsksWhenThresholdsAreMet() {
        XCTAssertTrue(
            ReviewPromptPolicy.shouldAsk(
                usedDayCount: 5,
                completedMovementCount: 10,
                reviewAskDecision: nil
            )
        )
        XCTAssertTrue(
            ReviewPromptPolicy.shouldAsk(
                usedDayCount: 6,
                completedMovementCount: 11,
                reviewAskDecision: nil
            )
        )
    }

    @MainActor func testReviewPromptPolicyNeverAsksAfterDecision() {
        for decision in [ReviewPromptDecision.accepted, .declined] {
            XCTAssertFalse(
                ReviewPromptPolicy.shouldAsk(
                    usedDayCount: 5,
                    completedMovementCount: 10,
                    reviewAskDecision: decision.rawValue
                )
            )
        }
    }

    @MainActor func testForegroundingCountsOneDayPerCalendarDay() {
        let store = DeskSettingsStore(defaults: defaults)

        store.recordAppForegroundDay()
        store.recordAppForegroundDay()

        XCTAssertEqual(store.settings.usedDayCount, 1)
        XCTAssertEqual(store.settings.lastUsedDayKey, ReviewPromptPolicy.dayKey())

        let relaunchedStore = DeskSettingsStore(defaults: defaults)
        relaunchedStore.recordAppForegroundDay()

        XCTAssertEqual(relaunchedStore.settings.usedDayCount, 1)
    }

    @MainActor func testForegroundingIncrementsWhenDayKeyChanges() throws {
        var stored = StoredDeskSettings()
        stored.usedDayCount = 4
        stored.lastUsedDayKey = "1999-12-31"
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)
        store.recordAppForegroundDay()

        XCTAssertEqual(store.settings.usedDayCount, 5)
        XCTAssertEqual(store.settings.lastUsedDayKey, ReviewPromptPolicy.dayKey())
    }

    @MainActor func testCompletedMovementsAreCountedAndPersisted() {
        let store = DeskSettingsStore(defaults: defaults)
        for _ in 0..<10 {
            store.recordCompletedMovement()
        }

        XCTAssertEqual(store.settings.completedMovementCount, 10)

        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.settings.completedMovementCount, 10)
    }

    @MainActor func testAcceptedReviewDecisionSuppressesPromptPermanently() throws {
        var stored = StoredDeskSettings()
        stored.usedDayCount = 5
        stored.completedMovementCount = 10
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)
        XCTAssertTrue(store.shouldAskForReview)

        store.recordReviewPromptDecision(.accepted)
        XCTAssertFalse(store.shouldAskForReview)

        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertFalse(relaunchedStore.shouldAskForReview)
        XCTAssertEqual(relaunchedStore.settings.reviewAskDecision, ReviewPromptDecision.accepted.rawValue)
    }

    @MainActor func testDeclinedReviewDecisionSuppressesPromptPermanently() throws {
        var stored = StoredDeskSettings()
        stored.usedDayCount = 5
        stored.completedMovementCount = 10
        defaults.set(try JSONEncoder().encode(stored), forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)
        XCTAssertTrue(store.shouldAskForReview)

        store.recordReviewPromptDecision(.declined)
        XCTAssertFalse(store.shouldAskForReview)

        let relaunchedStore = DeskSettingsStore(defaults: defaults)

        XCTAssertFalse(relaunchedStore.shouldAskForReview)
        XCTAssertEqual(relaunchedStore.settings.reviewAskDecision, ReviewPromptDecision.declined.rawValue)
    }

    @MainActor func testReviewPromptDecisionIsRecordedOnlyOnce() {
        let store = DeskSettingsStore(defaults: defaults)

        store.recordReviewPromptDecision(.declined)
        store.recordReviewPromptDecision(.accepted)

        XCTAssertEqual(store.settings.reviewAskDecision, ReviewPromptDecision.declined.rawValue)
    }

    @MainActor func testMalformedReviewFieldsFallBackToDefaultsAndKeepDeskSelection() throws {
        let deskID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "selectedDeskID": deskID.uuidString,
            "selectedDeskName": "Desk",
            "usedDayCount": "five",
            "lastUsedDayKey": 7,
            "completedMovementCount": ["ten"],
            "reviewAskDecision": 42,
        ])
        defaults.set(data, forKey: DeskSettingsStore.storageKey)

        let store = DeskSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.selectedDeskID, deskID)
        XCTAssertEqual(store.settings.usedDayCount, 0)
        XCTAssertNil(store.settings.lastUsedDayKey)
        XCTAssertEqual(store.settings.completedMovementCount, 0)
        XCTAssertNil(store.settings.reviewAskDecision)
        XCTAssertFalse(store.shouldAskForReview)
    }

    @MainActor func testDayKeyReflectsCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let beforeMidnight = Date(timeIntervalSince1970: 1_767_225_599)
        let afterMidnight = Date(timeIntervalSince1970: 1_767_225_601)

        XCTAssertEqual(ReviewPromptPolicy.dayKey(for: beforeMidnight, calendar: calendar), "2025-12-31")
        XCTAssertEqual(ReviewPromptPolicy.dayKey(for: afterMidnight, calendar: calendar), "2026-01-01")
    }
}
