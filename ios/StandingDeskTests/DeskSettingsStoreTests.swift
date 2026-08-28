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
}
