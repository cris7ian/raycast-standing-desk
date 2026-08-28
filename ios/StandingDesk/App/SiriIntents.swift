import AppIntents

enum DeskAppAction: Equatable {
    case move(PendingMovement)
    case stop
    case refreshHeight
}

protocol StandingDeskForegroundIntent: AppIntent {}

extension StandingDeskForegroundIntent {
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @MainActor
    func queue(
        _ action: DeskAppAction,
        dialog: IntentDialog
    ) -> some IntentResult & ProvidesDialog {
        AppShortcutHandler.shared.queue(action)
        return .result(dialog: dialog)
    }
}

struct MoveDeskToSitIntent: StandingDeskForegroundIntent {
    static let title: LocalizedStringResource = "Move Desk to Sit"
    static let description = IntentDescription("Moves the selected desk to the saved Sit height in the foreground.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        queue(.move(.sit), dialog: "Opening Standing Desk to move to Sit.")
    }
}

struct MoveDeskToStandIntent: StandingDeskForegroundIntent {
    static let title: LocalizedStringResource = "Move Desk to Stand"
    static let description = IntentDescription("Moves the selected desk to the saved Stand height in the foreground.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        queue(.move(.stand), dialog: "Opening Standing Desk to move to Stand.")
    }
}

struct StopDeskIntent: StandingDeskForegroundIntent {
    static let title: LocalizedStringResource = "Stop Desk"
    static let description = IntentDescription("Stops movement of the selected desk in the foreground.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        queue(.stop, dialog: "Opening Standing Desk to send Stop.")
    }
}

struct CheckDeskHeightIntent: StandingDeskForegroundIntent {
    static let title: LocalizedStringResource = "Check Desk Height"
    static let description = IntentDescription("Opens the app and reads the selected desk height.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        queue(.refreshHeight, dialog: "Opening Standing Desk to check the height.")
    }
}

struct StandingDeskSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveDeskToSitIntent(),
            phrases: [
                "Sit with \(.applicationName)",
                "Move my desk to Sit with \(.applicationName)",
            ],
            shortTitle: "Move to Sit",
            systemImageName: "sun.horizon"
        )

        AppShortcut(
            intent: MoveDeskToStandIntent(),
            phrases: [
                "Stand with \(.applicationName)",
                "Move my desk to Stand with \(.applicationName)",
            ],
            shortTitle: "Move to Stand",
            systemImageName: "sun.max"
        )

        AppShortcut(
            intent: StopDeskIntent(),
            phrases: [
                "Stop my desk with \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Stop Desk",
            systemImageName: "stop.circle"
        )

        AppShortcut(
            intent: CheckDeskHeightIntent(),
            phrases: [
                "Check my desk height with \(.applicationName)",
                "What is my desk height in \(.applicationName)",
            ],
            shortTitle: "Check Height",
            systemImageName: "ruler"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
