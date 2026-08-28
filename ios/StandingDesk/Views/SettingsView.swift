import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: DeskSettingsStore
    @EnvironmentObject private var bluetooth: DeskBluetoothController
    @State private var configuration = DeskConfiguration.default
    @State private var sitHeight = DeskConfiguration.defaultSitHeight
    @State private var standHeight = DeskConfiguration.defaultStandHeight
    @State private var errorMessage: String?
    @State private var showingForgetConfirmation = false
    @State private var saveConfirmation = 0
    @State private var showingSaved = false
    @State private var pendingMutation: PendingMutation?
    @State private var savedMessageTask: Task<Void, Never>?

    private enum PendingMutation {
        case configuration
        case restoreDefaults
        case selectDesk
        case forgetDesk

        var showsSavedConfirmation: Bool {
            switch self {
            case .configuration, .restoreDefaults:
                true
            case .selectDesk, .forgetDesk:
                false
            }
        }
    }

    private var mutationInFlight: Bool {
        pendingMutation != nil || bluetooth.settingsMutationState == .pending
    }

    var body: some View {
        Form {
            deskSection
            presetsSection
            limitsSection
            resetSection
            safetySection
        }
        .disabled(mutationInFlight)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(mutationInFlight)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveConfiguration()
                } label: {
                    if mutationInFlight {
                        ProgressView()
                            .accessibilityLabel("Updating settings")
                    } else if showingSaved {
                        Label("Saved", systemImage: "checkmark")
                    } else {
                        Text("Save")
                    }
                }
                .disabled(mutationInFlight)
            }
        }
        .onAppear {
            loadStoredConfiguration()
        }
        .onDisappear {
            bluetooth.stopScan()
            savedMessageTask?.cancel()
            savedMessageTask = nil
            showingSaved = false
        }
        .sensoryFeedback(.success, trigger: saveConfirmation)
        .onChange(of: bluetooth.settingsMutationState) { _, state in
            handleSaveState(state)
        }
        .confirmationDialog(
            "Forget this desk?",
            isPresented: $showingForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget Desk", role: .destructive) { forgetDesk() }
        } message: {
            Text("You must scan and select the desk before moving it again.")
        }
        .alert(
            "Settings Update Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var deskSection: some View {
        Section("Desk") {
            if let name = settingsStore.settings.selectedDeskName {
                LabeledContent("Selected", value: name)
            } else {
                Text("No desk selected")
                    .foregroundStyle(.secondary)
            }

            Button {
                bluetooth.startScan()
            } label: {
                Label(
                    bluetooth.connectionState == .scanning ? "Scanning…" : "Scan for Desks",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
            .disabled(bluetooth.connectionState == .scanning)

            ForEach(bluetooth.discoveredDesks) { desk in
                Button {
                    guard beginTrackedMutation(.selectDesk) else { return }
                    bluetooth.stopScan()
                    bluetooth.selectDesk(desk)
                    handleSaveState(bluetooth.settingsMutationState)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(desk.name)
                            Text("Nearby · \(desk.id.uuidString.suffix(4))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if settingsStore.settings.selectedDeskID == desk.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
            heightField("Sit", value: $sitHeight, icon: "sun.horizon")
            currentHeightButton("Use Current Height for Sit") {
                sitHeight = $0
            }
            heightField("Stand", value: $standHeight, icon: "sun.max.fill")
            currentHeightButton("Use Current Height for Stand") {
                standHeight = $0
            }
        }
    }

    private var limitsSection: some View {
        Section {
            heightField("Base", value: $configuration.baseHeight)
            heightField("Minimum", value: $configuration.minimumHeight)
            heightField("Maximum", value: $configuration.maximumHeight)
            heightField("Raise and Lower Step", value: $configuration.stepHeight)
        } header: {
            Text("Height Configuration")
        } footer: {
            Text("These values apply to future movement requests.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Restore Defaults") {
                guard beginTrackedMutation(.restoreDefaults) else { return }
                bluetooth.restoreDefaults()
                handleSaveState(bluetooth.settingsMutationState)
            }
            Button("Forget Desk", role: .destructive) {
                showingForgetConfirmation = true
            }
            .disabled(!settingsStore.hasSelectedDesk)
        }
    }

    private var safetySection: some View {
        Section("Safety") {
            Label("Keep the physical controller within reach.", systemImage: "hand.raised.fill")
            Label("The app sends Stop when it becomes inactive.", systemImage: "stop.fill")
            Label("Movement stops after 45 seconds or a detected stall.", systemImage: "timer")
        }
    }

    private func heightField(_ title: String, value: Binding<Double>, icon: String? = nil) -> some View {
        HStack {
            if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
            Text(title)
            Spacer()
            TextField("cm", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityLabel("\(title) height")
            Text("cm").foregroundStyle(.secondary)
        }
    }

    private func currentHeightButton(_ title: String, update: @escaping (Double) -> Void) -> some View {
        Button(title) {
            if let height = bluetooth.currentHeight { update(height) }
        }
        .disabled(bluetooth.currentHeight == nil)
    }

    private func saveConfiguration() {
        guard beginTrackedMutation(.configuration) else { return }
        do {
            try bluetooth.applyConfiguration(configuration, sitHeight: sitHeight, standHeight: standHeight)
            handleSaveState(bluetooth.settingsMutationState)
        } catch {
            pendingMutation = nil
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func beginTrackedMutation(_ mutation: PendingMutation) -> Bool {
        guard !mutationInFlight else { return false }
        savedMessageTask?.cancel()
        bluetooth.clearSettingsMutationState()
        pendingMutation = mutation
        showingSaved = false
        return true
    }

    private func forgetDesk() {
        guard beginTrackedMutation(.forgetDesk) else { return }
        bluetooth.forgetDesk()
        handleSaveState(bluetooth.settingsMutationState)
    }

    private func handleSaveState(_ state: DeskSettingsMutationState) {
        guard let mutation = pendingMutation else { return }
        switch state {
        case .idle, .pending:
            return
        case .succeeded:
            pendingMutation = nil
            loadStoredConfiguration()
            saveConfirmation += 1
            let confirmation = saveConfirmation
            bluetooth.clearSettingsMutationState()
            guard mutation.showsSavedConfirmation else { return }
            withAnimation(.easeInOut(duration: 0.15)) { showingSaved = true }
            savedMessageTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    return
                }
                guard confirmation == saveConfirmation else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingSaved = false
                }
            }
        case let .failed(message):
            pendingMutation = nil
            bluetooth.clearSettingsMutationState()
            if let controllerMessage = bluetooth.alertMessage {
                bluetooth.alertMessage = nil
                errorMessage = controllerMessage
            } else {
                errorMessage = message
            }
        }
    }

    private func loadStoredConfiguration() {
        configuration = settingsStore.settings.configuration
        sitHeight = settingsStore.settings.sitHeight
        standHeight = settingsStore.settings.standHeight
    }
}
