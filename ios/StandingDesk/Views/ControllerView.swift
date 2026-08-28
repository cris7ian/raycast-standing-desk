import SwiftUI

struct ControllerView: View {
    @EnvironmentObject private var settingsStore: DeskSettingsStore
    @EnvironmentObject private var bluetooth: DeskBluetoothController
    @State private var showingSafety = false
    @State private var pendingMovement: PendingMovement?
    @State private var pendingPresetSave: PresetSlot?
    @State private var savedPresetMessage: String?
    @State private var saveFeedback = 0
    @State private var savedMessageTask: Task<Void, Never>?

    private enum PresetSlot {
        case sit
        case stand

        var label: String {
            switch self {
            case .sit: "Sit"
            case .stand: "Stand"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                brandingSection
                statusSection
                positionsSection
                adjustmentSection
                utilitySection
                footerSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 46)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .tint(.primary)
                    .disabled(bluetooth.hasQueuedOrActiveMovement)
                }
            }
            .sheet(isPresented: $showingSafety, onDismiss: cancelPendingMovement) {
                SafetyAcknowledgementView {
                    settingsStore.acknowledgeSafety()
                    showingSafety = false
                    executePendingMovement()
                }
            }
            .alert(
                "Standing Desk",
                isPresented: Binding(
                    get: { bluetooth.alertMessage != nil },
                    set: { if !$0 { bluetooth.alertMessage = nil } }
                )
            ) {
                Button("OK") { bluetooth.alertMessage = nil }
            } message: {
                Text(bluetooth.alertMessage ?? "")
            }
            .onAppear {
                if settingsStore.hasSelectedDesk,
                   bluetooth.currentHeight == nil,
                   bluetooth.settingsMutationState != .pending,
                   !bluetooth.isRefreshingStatus,
                   !bluetooth.hasQueuedOrActiveMovement
                {
                    bluetooth.refreshStatus()
                }
            }
            .onDisappear {
                savedMessageTask?.cancel()
                savedMessageTask = nil
                savedPresetMessage = nil
            }
            .onChange(of: bluetooth.settingsMutationState) { _, state in
                handlePresetSave(state)
            }
            .sensoryFeedback(.success, trigger: saveFeedback)
        }
    }

    private var brandingSection: some View {
        Section {
            DeskLogo()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var statusSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(bluetooth.currentHeight.map(formatHeight) ?? "--.- cm")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()

                Spacer()

                Label(bluetooth.connectionState.label, systemImage: connectionIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            if !settingsStore.hasSelectedDesk {
                Label("Select a desk in Settings", systemImage: "deskclock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionsSection: some View {
        Section("Positions") {
            movementRow(
                "Sit",
                icon: "sunrise",
                detail: formatHeight(settingsStore.settings.sitHeight)
            ) {
                requestMovement(.sit)
            }

            movementRow(
                "Stand",
                icon: "sun.max",
                detail: formatHeight(settingsStore.settings.standHeight)
            ) {
                requestMovement(.stand)
            }
        }
        .disabled(!settingsStore.hasSelectedDesk)
    }

    private var adjustmentSection: some View {
        Section("Adjust") {
            movementRow(
                "Raise",
                icon: "arrow.up",
                detail: formatHeight(settingsStore.settings.configuration.stepHeight)
            ) {
                requestMovement(.nudge(settingsStore.settings.configuration.stepHeight))
            }
            .disabled(!settingsStore.hasSelectedDesk || bluetooth.currentHeight == nil)

            movementRow(
                "Lower",
                icon: "arrow.down",
                detail: formatHeight(settingsStore.settings.configuration.stepHeight)
            ) {
                requestMovement(.nudge(-settingsStore.settings.configuration.stepHeight))
            }
            .disabled(!settingsStore.hasSelectedDesk || bluetooth.currentHeight == nil)

            Button(role: .destructive) {
                bluetooth.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(!settingsStore.hasSelectedDesk)
            .accessibilityHint("Stops all desk movement")
        }
    }

    private var utilitySection: some View {
        Section {
            Menu {
                Button {
                    saveCurrentPosition(as: .sit)
                } label: {
                    Label("Save as Sit", systemImage: "sunrise")
                }

                Button {
                    saveCurrentPosition(as: .stand)
                } label: {
                    Label("Save as Stand", systemImage: "sun.max")
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .frame(width: 18)
                    Text(savedPresetMessage ?? "Save Current Position")
                    Spacer()
                    if pendingPresetSave != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .disabled(
                !settingsStore.hasSelectedDesk ||
                    bluetooth.currentHeight == nil ||
                    bluetooth.hasQueuedOrActiveMovement ||
                    pendingPresetSave != nil
            )

            actionRow("Refresh Height", icon: "arrow.clockwise") {
                bluetooth.refreshStatus()
            }
            .disabled(
                !settingsStore.hasSelectedDesk ||
                    bluetooth.isRefreshingStatus ||
                    bluetooth.hasQueuedOrActiveMovement
            )
        }
    }

    private var footerSection: some View {
        Section {
            Text("built by Cristian E. Caroli 🍕")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func movementRow(
        _ title: String,
        icon: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func requestMovement(_ movement: PendingMovement) {
        if settingsStore.hasAcknowledgedSafety {
            execute(movement)
        } else {
            pendingMovement = movement
            showingSafety = true
        }
    }

    private func cancelPendingMovement() {
        pendingMovement = nil
    }

    private func executePendingMovement() {
        guard let pendingMovement else { return }
        self.pendingMovement = nil
        execute(pendingMovement)
    }

    private func execute(_ movement: PendingMovement) {
        switch movement {
        case .sit:
            bluetooth.move(to: settingsStore.settings.sitHeight)
        case .stand:
            bluetooth.move(to: settingsStore.settings.standHeight)
        case let .nudge(delta):
            bluetooth.nudge(by: delta)
        }
    }

    private func saveCurrentPosition(as slot: PresetSlot) {
        guard let currentHeight = bluetooth.currentHeight else { return }
        savedMessageTask?.cancel()
        bluetooth.clearSettingsMutationState()
        pendingPresetSave = slot
        savedPresetMessage = nil

        do {
            let sitHeight = slot == .sit ? currentHeight : settingsStore.settings.sitHeight
            let standHeight = slot == .stand ? currentHeight : settingsStore.settings.standHeight
            try bluetooth.applyConfiguration(
                settingsStore.settings.configuration,
                sitHeight: sitHeight,
                standHeight: standHeight
            )
            handlePresetSave(bluetooth.settingsMutationState)
        } catch {
            pendingPresetSave = nil
            bluetooth.alertMessage = error.localizedDescription
        }
    }

    private func handlePresetSave(_ state: DeskSettingsMutationState) {
        guard let slot = pendingPresetSave else { return }
        switch state {
        case .idle, .pending:
            return
        case .succeeded:
            pendingPresetSave = nil
            savedPresetMessage = "Saved as \(slot.label)"
            saveFeedback += 1
            bluetooth.clearSettingsMutationState()
            let message = savedPresetMessage
            savedMessageTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    return
                }
                guard savedPresetMessage == message else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    savedPresetMessage = nil
                }
            }
        case let .failed(message):
            pendingPresetSave = nil
            bluetooth.clearSettingsMutationState()
            if bluetooth.alertMessage == nil {
                bluetooth.alertMessage = message
            }
        }
    }

    private var connectionIcon: String {
        switch bluetooth.connectionState {
        case .connected, .moving, .stopping: "antenna.radiowaves.left.and.right"
        case .scanning, .connecting: "ellipsis"
        case .disconnected, .bluetoothUnavailable: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private func formatHeight(_ height: Double) -> String {
        "\(height.formatted(.number.precision(.fractionLength(1)))) cm"
    }
}

private struct DeskLogo: View {
    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .frame(width: 76, height: 14)

            HStack(alignment: .top, spacing: 28) {
                Capsule()
                    .frame(width: 12, height: 50)
                Capsule()
                    .frame(width: 12, height: 40)
            }
            .padding(.top, 7)
        }
        .foregroundStyle(.black)
        .frame(width: 76, height: 57, alignment: .top)
    }
}
