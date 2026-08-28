import SwiftUI
import UIKit

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
            creditsSection
        }
        .background(KeyboardDismissInstaller())
        .scrollDismissesKeyboard(.interactively)
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
                    bluetooth.connectionState == .scanning
                        ? appString("Scanning…")
                        : appString("Scan for Desks"),
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
            heightField(appString("Sit"), value: $sitHeight, icon: "sun.horizon")
            currentHeightButton(appString("Use Current Height for Sit")) {
                sitHeight = $0
            }
            heightField(appString("Stand"), value: $standHeight, icon: "sun.max.fill")
            currentHeightButton(appString("Use Current Height for Stand")) {
                standHeight = $0
            }
        }
    }

    private var limitsSection: some View {
        Section {
            heightField(appString("Base"), value: $configuration.baseHeight)
            heightField(appString("Minimum"), value: $configuration.minimumHeight)
            heightField(appString("Maximum"), value: $configuration.maximumHeight)
            heightField(appString("Raise and Lower Step"), value: $configuration.stepHeight)
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

    private var creditsSection: some View {
        Section {
            Text("built by Cristian E. Caroli 🍕")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func heightField(_ title: String, value: Binding<Double>, icon: String? = nil) -> some View {
        HStack {
            if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
            Text(title)
            Spacer()
            SelectAllNumberField(value: value, accessibilityLabel: appFormat("%@ height", title))
                .frame(width: 90)
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
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        guard beginTrackedMutation(.configuration) else { return }
        do {
            try bluetooth.applyConfiguration(configuration, sitHeight: sitHeight, standHeight: standHeight)
            handleSaveState(bluetooth.settingsMutationState)
        } catch {
            pendingMutation = nil
            errorMessage = localizedAppError(error)
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

private struct SelectAllNumberField: UIViewRepresentable {
    @Binding var value: Double
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.font = .preferredFont(forTextStyle: .body)
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.accessibilityLabel = accessibilityLabel
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.value = $value
        textField.accessibilityLabel = accessibilityLabel
        guard !textField.isFirstResponder else { return }
        context.coordinator.renderValue(in: textField)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>
        private let formatter: NumberFormatter

        init(value: Binding<Double>) {
            self.value = value
            formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }

        @objc func textChanged(_ textField: UITextField) {
            guard let number = formatter.number(from: textField.text ?? "") else { return }
            value.wrappedValue = number.doubleValue
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            Task { @MainActor [weak textField] in
                await Task.yield()
                guard textField?.isFirstResponder == true else { return }
                textField?.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            textChanged(textField)
            renderValue(in: textField)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        func renderValue(in textField: UITextField) {
            textField.text = formatter.string(from: NSNumber(value: value.wrappedValue))
        }
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissView {
        KeyboardDismissView()
    }

    func updateUIView(_ view: KeyboardDismissView, context: Context) {}
}

@MainActor
private final class KeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var recognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard installedWindow !== window else { return }
        installedWindow?.removeGestureRecognizer(recognizer)
        installedWindow = window
        window?.addGestureRecognizer(recognizer)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            installedWindow?.removeGestureRecognizer(recognizer)
            installedWindow = nil
        }
        super.willMove(toWindow: newWindow)
    }

    @objc private func dismissKeyboard() {
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }
}
