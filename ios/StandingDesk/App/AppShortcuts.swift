import Combine
import UIKit

enum DeskQuickAction: String, CaseIterable, Equatable {
    case sit = "com.salsaparapizza.standingdesk.sit"
    case stand = "com.salsaparapizza.standingdesk.stand"

    var appAction: DeskAppAction {
        switch self {
        case .sit: .move(.sit)
        case .stand: .move(.stand)
        }
    }

    var localizedTitle: String {
        switch self {
        case .sit: appString("Sit")
        case .stand: appString("Stand")
        }
    }

    var systemImageName: String {
        switch self {
        case .sit: "sun.horizon"
        case .stand: "sun.max"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: localizedTitle,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: nil
        )
    }
}

@MainActor
final class AppShortcutHandler: ObservableObject {
    static let shared = AppShortcutHandler()

    @Published private(set) var pendingAction: DeskAppAction?

    private init() {}

    @discardableResult
    func queue(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = DeskQuickAction(rawValue: shortcutItem.type) else { return false }
        pendingAction = action.appAction
        return true
    }

    func queue(_ action: DeskAppAction) {
        pendingAction = action
    }

    func consumePendingAction() -> DeskAppAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}

@MainActor
final class StandingDeskAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = DeskQuickAction.allCases.map(\.shortcutItem)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = StandingDeskSceneDelegate.self
        return configuration
    }
}

@MainActor
final class StandingDeskSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        AppShortcutHandler.shared.queue(shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppShortcutHandler.shared.queue(shortcutItem))
    }
}
