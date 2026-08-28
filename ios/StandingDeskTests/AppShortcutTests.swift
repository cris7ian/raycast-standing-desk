import XCTest
@testable import StandingDesk

final class AppShortcutTests: XCTestCase {
    func testQuickActionTypesRemainStable() {
        XCTAssertEqual(DeskQuickAction.sit.rawValue, "com.salsaparapizza.standingdesk.sit")
        XCTAssertEqual(DeskQuickAction.stand.rawValue, "com.salsaparapizza.standingdesk.stand")
    }

    func testQuickActionsMapToMovementPresets() {
        switch DeskQuickAction.sit.appAction {
        case .move(.sit): break
        default: XCTFail("Sit shortcut must map to the Sit preset")
        }

        switch DeskQuickAction.stand.appAction {
        case .move(.stand): break
        default: XCTFail("Stand shortcut must map to the Stand preset")
        }
    }

    func testUnknownQuickActionIsRejected() {
        XCTAssertNil(DeskQuickAction(rawValue: "com.salsaparapizza.standingdesk.unknown"))
    }

    @MainActor func testHandlerQueuesAndConsumesKnownAction() {
        let handler = AppShortcutHandler.shared
        _ = handler.consumePendingAction()

        XCTAssertTrue(handler.queue(DeskQuickAction.sit.shortcutItem))
        XCTAssertEqual(handler.pendingAction, .move(.sit))
        XCTAssertEqual(handler.consumePendingAction(), .move(.sit))
        XCTAssertNil(handler.pendingAction)
    }

    func testSupportedLocalizationsAreBundled() throws {
        let expectedTranslations = [
            "de": (settings: "Einstellungen", privacy: "Datenschutzrichtlinie"),
            "es": (settings: "Ajustes", privacy: "Política de privacidad"),
            "fr": (settings: "Réglages", privacy: "Politique de confidentialité"),
            "it": (settings: "Impostazioni", privacy: "Informativa sulla privacy"),
        ]

        for (language, expected) in expectedTranslations {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(
                bundle.localizedString(forKey: "Settings", value: nil, table: nil),
                expected.settings
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "Privacy Policy", value: nil, table: nil),
                expected.privacy
            )
            XCTAssertNotEqual(
                bundle.localizedString(
                    forKey: "NSBluetoothAlwaysUsageDescription",
                    value: nil,
                    table: "InfoPlist"
                ),
                "NSBluetoothAlwaysUsageDescription"
            )
        }
    }
}
