import SwiftUI

@main
struct StandingDeskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsStore: DeskSettingsStore
    @StateObject private var bluetooth: DeskBluetoothController

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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if settingsStore.hasSelectedDesk,
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
