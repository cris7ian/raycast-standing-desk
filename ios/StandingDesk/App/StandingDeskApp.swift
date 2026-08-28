import SwiftUI

@main
struct StandingDeskApp: App {
    @UIApplicationDelegateAdaptor(StandingDeskAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: DeskSettingsStore
    @StateObject private var bluetooth: DeskBluetoothController
    @StateObject private var shortcutHandler = AppShortcutHandler.shared

    init() {
        let settingsStore = DeskSettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _bluetooth = StateObject(wrappedValue: DeskBluetoothController(settingsStore: settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            ControllerView()
                .environmentObject(settingsStore)
                .environmentObject(bluetooth)
                .environmentObject(shortcutHandler)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if shortcutHandler.pendingAction == nil,
                   settingsStore.hasSelectedDesk,
                   bluetooth.connectionState != .scanning,
                   bluetooth.settingsMutationState != .pending,
                   !bluetooth.isRefreshingStatus,
                   !bluetooth.hasQueuedOrActiveMovement
                {
                    bluetooth.refreshStatus()
                }
            } else {
                bluetooth.stopForAppLifecycle()
            }
        }
    }
}
