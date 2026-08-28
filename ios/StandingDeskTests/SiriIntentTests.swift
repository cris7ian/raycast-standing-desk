import AppIntents
import XCTest
@testable import StandingDesk

final class SiriIntentTests: XCTestCase {
    func testSiriIntentsOpenTheAppAndRequireLocalAuthentication() {
        XCTAssertTrue(MoveDeskToSitIntent.openAppWhenRun)
        XCTAssertTrue(MoveDeskToStandIntent.openAppWhenRun)
        XCTAssertTrue(StopDeskIntent.openAppWhenRun)
        XCTAssertTrue(CheckDeskHeightIntent.openAppWhenRun)

        XCTAssertEqual(MoveDeskToSitIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
        XCTAssertEqual(MoveDeskToStandIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
        XCTAssertEqual(StopDeskIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
        XCTAssertEqual(CheckDeskHeightIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
    }

    func testSiriProviderPublishesCompleteSafeControlSet() {
        XCTAssertEqual(StandingDeskSiriShortcuts.appShortcuts.count, 4)
    }

    @MainActor func testHandlerQueuesEverySiriAction() {
        let handler = AppShortcutHandler.shared
        _ = handler.consumePendingAction()

        let actions: [DeskAppAction] = [
            .move(.sit),
            .move(.stand),
            .stop,
            .refreshHeight,
        ]

        for action in actions {
            handler.queue(action)
            XCTAssertEqual(handler.consumePendingAction(), action)
        }
    }

    @MainActor func testSiriIntentsQueueTheirExpectedActions() async throws {
        let handler = AppShortcutHandler.shared
        _ = handler.consumePendingAction()

        _ = try await MoveDeskToSitIntent().perform()
        XCTAssertEqual(handler.consumePendingAction(), .move(.sit))

        _ = try await MoveDeskToStandIntent().perform()
        XCTAssertEqual(handler.consumePendingAction(), .move(.stand))

        _ = try await StopDeskIntent().perform()
        XCTAssertEqual(handler.consumePendingAction(), .stop)

        _ = try await CheckDeskHeightIntent().perform()
        XCTAssertEqual(handler.consumePendingAction(), .refreshHeight)
    }

    func testSiriPhrasesAreLocalized() throws {
        let expectedTranslations = [
            "de": "Mit ${applicationName} sitzen",
            "es": "Sentarme con ${applicationName}",
            "fr": "M’asseoir avec ${applicationName}",
            "it": "Sedermi con ${applicationName}",
        ]

        for (language, expectedPhrase) in expectedTranslations {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(
                bundle.localizedString(
                    forKey: "Sit with ${applicationName}",
                    value: nil,
                    table: "AppShortcuts"
                ),
                expectedPhrase
            )
        }
    }
}
