import Combine
@preconcurrency import CoreBluetooth
import UIKit

enum DeskSettingsMutationState: Equatable {
    case idle
    case pending
    case succeeded
    case failed(String)
}

enum DeskRequestDisposition: Equatable {
    case activate
    case queue
    case stopThenQueue
}

enum DeskCentralStateDisposition: Equatable {
    case ready
    case wait
    case unavailable
}

func deskCentralStateDisposition(for state: CBManagerState) -> DeskCentralStateDisposition {
    switch state {
    case .poweredOn:
        .ready
    case .unknown:
        .wait
    case .resetting, .unsupported, .unauthorized, .poweredOff:
        .unavailable
    @unknown default:
        .unavailable
    }
}

private func bluetoothUnavailableMessage(for state: CBManagerState) -> String {
    switch state {
    case .unauthorized:
        "Bluetooth permission denied"
    case .poweredOff:
        "Bluetooth is off"
    case .unsupported:
        "Bluetooth Low Energy unavailable"
    case .resetting, .unknown:
        "Bluetooth is unavailable"
    case .poweredOn:
        "Bluetooth is available"
    @unknown default:
        "Bluetooth state is unsupported"
    }
}

enum DeskOperationKind: Equatable {
    case status
    case move
    case stop
}

func deskHasRequiredCharacteristics(
    for operation: DeskOperationKind,
    hasControl: Bool,
    hasOutput: Bool,
    hasInput: Bool
) -> Bool {
    switch operation {
    case .status:
        hasOutput
    case .move:
        hasControl && hasOutput && hasInput
    case .stop:
        hasControl
    }
}

func deskRequestDisposition(
    replacingMovement: Bool,
    stopInProgress: Bool,
    canSendStop: Bool
) -> DeskRequestDisposition {
    if stopInProgress { return .queue }
    if replacingMovement, canSendStop { return .stopThenQueue }
    return .activate
}

@MainActor
final class DeskBluetoothController: NSObject, ObservableObject {
    @Published private(set) var connectionState: DeskConnectionState = .disconnected
    @Published private(set) var discoveredDesks: [DiscoveredDesk] = []
    @Published private(set) var currentHeight: Double?
    @Published private(set) var currentSpeed = 0.0
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var settingsMutationState: DeskSettingsMutationState = .idle
    @Published var alertMessage: String?

    var hasQueuedOrActiveMovement: Bool {
        if case .move = operation { return true }
        if case .move = pendingAfterStop { return true }
        return finalStopGeneration != nil
    }

    private struct OperationSnapshot {
        let deskID: UUID
        let selectionGeneration: UUID
        let configuration: DeskConfiguration
    }

    private enum Operation {
        case status(id: UUID, snapshot: OperationSnapshot)
        case move(id: UUID, target: Double, snapshot: OperationSnapshot)
        case stop(id: UUID, snapshot: OperationSnapshot)

        var id: UUID {
            switch self {
            case let .status(id, _), let .move(id, _, _), let .stop(id, _): id
            }
        }

        var snapshot: OperationSnapshot {
            switch self {
            case let .status(_, snapshot), let .move(_, _, snapshot), let .stop(_, snapshot): snapshot
            }
        }

        var isMovement: Bool {
            if case .move = self { return true }
            return false
        }

        var kind: DeskOperationKind {
            switch self {
            case .status: .status
            case .move: .move
            case .stop: .stop
            }
        }

        func replacingID(with id: UUID) -> Operation {
            switch self {
            case let .status(_, snapshot): .status(id: id, snapshot: snapshot)
            case let .move(_, target, snapshot): .move(id: id, target: target, snapshot: snapshot)
            case let .stop(_, snapshot): .stop(id: id, snapshot: snapshot)
            }
        }
    }

    private enum PendingMutation {
        case select(DiscoveredDesk)
        case forget
        case configuration(DeskConfiguration, sitHeight: Double, standHeight: Double)
        case restoreDefaults
    }

    private enum ControlWrite: Equatable {
        case setup(UUID)
        case finalStop(UUID)
    }

    private struct QueuedControlWrite: Equatable {
        let data: Data
        let purpose: ControlWrite
    }

    private let settingsStore: DeskSettingsStore
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var outputCharacteristic: CBCharacteristic?
    private var inputCharacteristic: CBCharacteristic?

    private var operation: Operation?
    private var pendingAfterStop: Operation?
    private var pendingMutation: PendingMutation?
    private var requestGeneration = UUID()
    private var finalStopGeneration: UUID?
    private var pendingControlWrites: [QueuedControlWrite] = []
    private var controlWriteInFlight: QueuedControlWrite?
    private var targetWriteInFlightGeneration: UUID?

    private var scanRequested = false
    private var connectionTimeout: DispatchWorkItem?
    private var initialReadingTimeout: DispatchWorkItem?
    private var scanTimeout: DispatchWorkItem?
    private var finalStopTimeout: DispatchWorkItem?
    private var movementSetupTimeout: DispatchWorkItem?
    private var movementTimer: Timer?
    private var movementStartedAt: Date?
    private var movementEvaluator: DeskMovementEvaluator?
    private var previousReading: DeskReading?
    private var movementSetupScheduledFor: UUID?
    private var movementBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(settingsStore: DeskSettingsStore) {
        self.settingsStore = settingsStore
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    isolated deinit {
        movementTimer?.invalidate()
        connectionTimeout?.cancel()
        initialReadingTimeout?.cancel()
        scanTimeout?.cancel()
        finalStopTimeout?.cancel()
        movementSetupTimeout?.cancel()
    }

    func startScan() {
        guard !hasQueuedOrActiveMovement else {
            alertMessage = "Wait for the desk to stop before scanning."
            return
        }
        if case .status = operation {
            invalidateActiveOperation()
        } else if operation != nil || pendingAfterStop != nil {
            alertMessage = "Wait for the current desk request before scanning."
            return
        }
        stopScan()
        discoveredDesks = []
        scanRequested = true
        connectionState = .scanning
        switch deskCentralStateDisposition(for: central.state) {
        case .ready:
            beginScan()
        case .wait:
            scheduleScanTimeout()
        case .unavailable:
            scanRequested = false
            handleBluetoothUnavailable(bluetoothUnavailableMessage(for: central.state))
        }
    }

    func stopScan() {
        scanRequested = false
        scanTimeout?.cancel()
        scanTimeout = nil
        if central?.state == .poweredOn {
            central.stopScan()
        }
        if connectionState == .scanning {
            connectionState = peripheral?.state == .connected ? .connected : .disconnected
        }
    }

    func selectDesk(_ desk: DiscoveredDesk) {
        requestMutation(.select(desk))
    }

    func forgetDesk() {
        requestMutation(.forget)
    }

    func applyConfiguration(_ configuration: DeskConfiguration, sitHeight: Double, standHeight: Double) throws {
        let configuration = try configuration.validated()
        let sitHeight = try configuration.validatedTarget(sitHeight)
        let standHeight = try configuration.validatedTarget(standHeight)
        requestMutation(.configuration(configuration, sitHeight: sitHeight, standHeight: standHeight))
    }

    func restoreDefaults() {
        requestMutation(.restoreDefaults)
    }

    func clearSettingsMutationState() {
        guard settingsMutationState != .pending else { return }
        settingsMutationState = .idle
    }

    func refreshStatus() {
        guard let snapshot = makeSnapshot() else { return }
        requestOperation(.status(id: UUID(), snapshot: snapshot))
    }

    func move(to requestedTarget: Double) {
        guard settingsStore.hasAcknowledgedSafety else {
            alertMessage = "Review and accept the safety checklist before moving the desk."
            return
        }
        guard let snapshot = makeSnapshot() else { return }
        do {
            let target = try snapshot.configuration.validatedTarget(requestedTarget)
            requestMove(.move(id: UUID(), target: target, snapshot: snapshot))
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func nudge(by delta: Double) {
        guard let currentHeight else {
            alertMessage = "Refresh the desk height before using Raise or Lower."
            return
        }
        let configuration = settingsStore.settings.configuration
        guard let target = nudgedTarget(
            currentHeight: currentHeight,
            delta: delta,
            minimumHeight: configuration.minimumHeight,
            maximumHeight: configuration.maximumHeight
        ) else {
            alertMessage = "The requested adjustment conflicts with the configured limits."
            return
        }
        move(to: target)
    }

    func stop() {
        let snapshot = operation?.snapshot ?? pendingAfterStop?.snapshot ?? makeSnapshot()
        invalidateActiveOperation()
        pendingAfterStop = nil
        cancelPendingMutation("Settings change was cancelled by Stop.")
        if finalStopGeneration != nil {
            return
        }
        if peripheral?.state == .connected, controlCharacteristic != nil {
            startFinalStop()
        } else {
            guard let snapshot else { return }
            activate(.stop(id: requestGeneration, snapshot: snapshot))
        }
    }

    func stopForAppLifecycle() {
        guard hasQueuedOrActiveMovement else { return }
        invalidateActiveOperation()
        pendingAfterStop = nil
        cancelPendingMutation("Settings change was cancelled because the app became inactive.")
        if finalStopGeneration == nil {
            startFinalStop()
        }
    }

    private func makeSnapshot() -> OperationSnapshot? {
        guard let deskID = settingsStore.settings.selectedDeskID,
              let selectionGeneration = settingsStore.settings.selectionGeneration
        else {
            alertMessage = "Select a desk in Settings first."
            return nil
        }
        do {
            return OperationSnapshot(
                deskID: deskID,
                selectionGeneration: selectionGeneration,
                configuration: try settingsStore.settings.configuration.validated()
            )
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }

    private func snapshotIsCurrent(_ snapshot: OperationSnapshot) -> Bool {
        settingsStore.settings.selectedDeskID == snapshot.deskID &&
            settingsStore.settings.selectionGeneration == snapshot.selectionGeneration &&
            settingsStore.settings.configuration == snapshot.configuration
    }

    @discardableResult
    private func newGeneration() -> UUID {
        requestGeneration = UUID()
        return requestGeneration
    }

    private func invalidateActiveOperation() {
        newGeneration()
        connectionTimeout?.cancel()
        connectionTimeout = nil
        movementTimer?.invalidate()
        movementTimer = nil
        movementStartedAt = nil
        movementEvaluator = nil
        previousReading = nil
        movementSetupScheduledFor = nil
        movementSetupTimeout?.cancel()
        movementSetupTimeout = nil
        initialReadingTimeout?.cancel()
        initialReadingTimeout = nil
        operation = nil
        isRefreshingStatus = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func requestMove(_ move: Operation) {
        requestOperation(move)
    }

    private func requestOperation(_ requestedOperation: Operation) {
        stopScan()
        let replacingMovement = operation?.isMovement == true || pendingAfterStop?.isMovement == true
        cancelPendingMutation("Settings change was cancelled by a newer desk request.")
        invalidateActiveOperation()
        pendingAfterStop = nil
        let replacement = requestedOperation.replacingID(with: requestGeneration)
        let disposition = deskRequestDisposition(
            replacingMovement: replacingMovement,
            stopInProgress: finalStopGeneration != nil,
            canSendStop: peripheral?.state == .connected && controlCharacteristic != nil
        )
        switch disposition {
        case .queue:
            pendingAfterStop = replacement
        case .stopThenQueue:
            pendingAfterStop = replacement
            startFinalStop()
        case .activate:
            activate(replacement)
        }
    }

    private func activate(_ nextOperation: Operation) {
        guard nextOperation.id == requestGeneration else { return }
        guard snapshotIsCurrent(nextOperation.snapshot) else { return }
        operation = nextOperation
        isRefreshingStatus = nextOperation.kind == .status
        connectSelectedDesk(for: nextOperation)
    }

    private func requestMutation(_ mutation: PendingMutation) {
        stopScan()
        invalidateActiveOperation()
        pendingAfterStop = nil
        pendingMutation = mutation
        settingsMutationState = .pending
        if finalStopGeneration != nil { return }
        if peripheral?.state == .connected, controlCharacteristic != nil {
            startFinalStop()
        } else {
            completeMutation()
        }
    }

    private func completeMutation() {
        guard let mutation = pendingMutation else { return }
        pendingMutation = nil
        do {
            settingsStore.clearLastSaveResult()
            switch mutation {
            case let .select(desk):
                disconnectCurrentDesk()
                settingsStore.selectDesk(id: desk.id, name: desk.name)
                clearCachedStatus()
            case .forget:
                disconnectCurrentDesk()
                settingsStore.forgetDesk()
                clearCachedStatus()
            case let .configuration(configuration, sitHeight, standHeight):
                let baseHeightChanged = configuration.baseHeight != settingsStore.settings.configuration.baseHeight
                try settingsStore.updateConfiguration(
                    configuration,
                    sitHeight: sitHeight,
                    standHeight: standHeight
                )
                if baseHeightChanged {
                    clearCachedStatus()
                }
            case .restoreDefaults:
                settingsStore.restoreDefaults()
                clearCachedStatus()
            }
            switch settingsStore.lastSaveResult?.outcome {
            case .saved:
                settingsMutationState = .succeeded
            case let .failed(message):
                settingsMutationState = .failed(message)
                alertMessage = message
            case nil:
                let message = "The settings change could not be verified."
                settingsMutationState = .failed(message)
                alertMessage = message
            }
        } catch {
            settingsMutationState = .failed(error.localizedDescription)
            alertMessage = error.localizedDescription
        }
    }

    private func cancelPendingMutation(_ message: String) {
        guard pendingMutation != nil else { return }
        pendingMutation = nil
        settingsMutationState = .failed(message)
    }

    private func clearCachedStatus() {
        currentHeight = nil
        currentSpeed = 0
    }

    private func beginScan() {
        guard scanRequested, central.state == .poweredOn else { return }
        central.stopScan()
        connectionState = .scanning
        if let selectedID = settingsStore.settings.selectedDeskID,
           let remembered = central.retrievePeripherals(withIdentifiers: [selectedID]).first
        {
            addDiscoveredDesk(remembered, rssi: 0, connected: remembered.state == .connected)
        }
        for desk in central.retrieveConnectedPeripherals(withServices: [DeskProtocol.controlServiceUUID]) {
            addDiscoveredDesk(desk, rssi: 0, connected: true)
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scheduleScanTimeout()
    }

    private func scheduleScanTimeout() {
        scanTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    private func connectSelectedDesk(for expectedOperation: Operation) {
        guard operation?.id == expectedOperation.id,
              expectedOperation.id == requestGeneration,
              snapshotIsCurrent(expectedOperation.snapshot)
        else { return }

        switch deskCentralStateDisposition(for: central.state) {
        case .ready:
            break
        case .wait:
            connectionState = .connecting
            scheduleConnectionTimeout(for: expectedOperation)
            return
        case .unavailable:
            handleBluetoothUnavailable(bluetoothUnavailableMessage(for: central.state))
            return
        }

        if let peripheral, peripheral.identifier == expectedOperation.snapshot.deskID {
            switch peripheral.state {
            case .connected:
                prepareConnectedDesk(peripheral, for: expectedOperation)
                return
            case .connecting:
                connectionState = .connecting
                scheduleConnectionTimeout(for: expectedOperation)
                return
            case .disconnecting:
                connectionState = .connecting
                scheduleConnectionTimeout(for: expectedOperation)
                retryConnectionAfterDisconnect(for: expectedOperation)
                return
            case .disconnected:
                break
            @unknown default:
                break
            }
        }
        guard let selected = central.retrievePeripherals(withIdentifiers: [expectedOperation.snapshot.deskID]).first else {
            fail("The selected desk is unavailable. Scan for it again in Settings.")
            return
        }
        disconnectCurrentDesk()
        peripheral = selected
        selected.delegate = self
        switch selected.state {
        case .connected:
            prepareConnectedDesk(selected, for: expectedOperation)
        case .connecting:
            connectionState = .connecting
            scheduleConnectionTimeout(for: expectedOperation)
        case .disconnecting:
            connectionState = .connecting
            scheduleConnectionTimeout(for: expectedOperation)
            retryConnectionAfterDisconnect(for: expectedOperation)
        case .disconnected:
            connectionState = .connecting
            central.connect(selected, options: nil)
            scheduleConnectionTimeout(for: expectedOperation)
        @unknown default:
            fail("The selected desk is in an unsupported connection state.")
        }
    }

    private func prepareConnectedDesk(_ connectedPeripheral: CBPeripheral, for expectedOperation: Operation) {
        guard operation?.id == expectedOperation.id,
              expectedOperation.id == requestGeneration,
              snapshotIsCurrent(expectedOperation.snapshot),
              connectedPeripheral === peripheral
        else { return }

        connectedPeripheral.delegate = self
        connectionState = .connecting
        scheduleConnectionTimeout(for: expectedOperation)
        if operationIsReady(expectedOperation) {
            startOperationWhenReady(expectedOperation)
        } else {
            connectedPeripheral.discoverServices([
                DeskProtocol.controlServiceUUID,
                DeskProtocol.outputServiceUUID,
                DeskProtocol.inputServiceUUID,
            ])
        }
    }

    private func operationIsReady(_ expectedOperation: Operation) -> Bool {
        deskHasRequiredCharacteristics(
            for: expectedOperation.kind,
            hasControl: controlCharacteristic != nil,
            hasOutput: outputCharacteristic != nil,
            hasInput: inputCharacteristic != nil
        )
    }

    private func scheduleConnectionTimeout(for expectedOperation: Operation) {
        connectionTimeout?.cancel()
        let operationID = expectedOperation.id
        let stopOperation = expectedOperation.kind == .stop
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  self.operation?.id == operationID,
                  self.requestGeneration == operationID
            else { return }
            let message = "Connection timed out. Put the desk in pairing mode and quit other desk-control apps."
            if stopOperation {
                self.failUnconfirmedStop(message)
            } else {
                self.fail(message)
            }
        }
        connectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func retryConnectionAfterDisconnect(for expectedOperation: Operation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self,
                  self.operation?.id == expectedOperation.id,
                  self.requestGeneration == expectedOperation.id,
                  self.snapshotIsCurrent(expectedOperation.snapshot)
            else { return }
            self.connectSelectedDesk(for: expectedOperation)
        }
    }

    private func disconnectCurrentDesk() {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        initialReadingTimeout?.cancel()
        initialReadingTimeout = nil
        if let peripheral,
           peripheral.state != .disconnected,
           central.state == .poweredOn
        {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        clearConnectionResources()
    }

    private func clearConnectionResources() {
        controlCharacteristic = nil
        outputCharacteristic = nil
        inputCharacteristic = nil
        pendingControlWrites = []
        controlWriteInFlight = nil
        targetWriteInFlightGeneration = nil
    }

    private func startOperationWhenReady(_ expectedOperation: Operation? = nil) {
        guard let peripheral,
              peripheral.identifier == settingsStore.settings.selectedDeskID,
              let operation,
              operation.id == requestGeneration,
              expectedOperation?.id == nil || expectedOperation?.id == operation.id,
              snapshotIsCurrent(operation.snapshot),
              operationIsReady(operation)
        else { return }

        switch operation {
        case .status:
            guard let outputCharacteristic else { return }
            connectionTimeout?.cancel()
            scheduleInitialReadingTimeout(for: operation)
            peripheral.readValue(for: outputCharacteristic)
        case let .move(id, target, _):
            guard controlCharacteristic != nil, inputCharacteristic != nil, let outputCharacteristic else { return }
            connectionTimeout?.cancel()
            scheduleInitialReadingTimeout(for: operation)
            connectionState = .moving(target: target)
            peripheral.setNotifyValue(true, for: outputCharacteristic)
            peripheral.readValue(for: outputCharacteristic)
            requestGeneration = id
        case .stop:
            guard controlCharacteristic != nil else { return }
            connectionTimeout?.cancel()
            invalidateActiveOperation()
            startFinalStop()
        }
    }

    private func scheduleInitialReadingTimeout(for expectedOperation: Operation) {
        initialReadingTimeout?.cancel()
        let operationID = expectedOperation.id
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  self.operation?.id == operationID,
                  self.requestGeneration == operationID
            else { return }
            self.fail("Timed out while reading the desk height. No movement target was sent.")
        }
        initialReadingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func beginMovement(id: UUID, target: Double, snapshot: OperationSnapshot, reading: DeskReading) {
        guard id == requestGeneration,
              operation?.id == id,
              snapshotIsCurrent(snapshot)
        else { return }

        if abs(reading.heightCm - target) <= DeskProtocol.targetToleranceCm {
            pendingAfterStop = nil
            invalidateActiveOperation()
            startFinalStop()
            return
        }
        guard rawTarget(for: target, baseHeight: snapshot.configuration.baseHeight) != nil else {
            failMovement("Target height cannot be represented by this desk controller.")
            return
        }

        movementStartedAt = Date()
        movementEvaluator = DeskMovementEvaluator(targetHeight: target)
        previousReading = reading
        UIApplication.shared.isIdleTimerDisabled = true
        beginMovementBackgroundTask()
        writeControl(DeskProtocol.wakePayload, purpose: .setup(id))
        writeControl(DeskProtocol.stopPayload, purpose: .setup(id))
        if let controlCharacteristic, writeType(for: controlCharacteristic) == .withoutResponse {
            scheduleMovementTargetWrites(id: id, target: target, snapshot: snapshot)
        } else {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self,
                      self.requestGeneration == id,
                      self.operation?.id == id,
                      self.movementSetupScheduledFor != id
                else { return }
                self.failMovement("The desk did not acknowledge movement setup and was stopped.")
            }
            movementSetupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        }
    }

    private func scheduleMovementTargetWrites(id: UUID, target: Double, snapshot: OperationSnapshot) {
        guard movementSetupScheduledFor != id else { return }
        movementSetupTimeout?.cancel()
        movementSetupTimeout = nil
        movementSetupScheduledFor = id
        DispatchQueue.main.asyncAfter(deadline: .now() + DeskProtocol.movementSetupDelay) { [weak self] in
            guard let self,
                  self.requestGeneration == id,
                  self.operation?.id == id
            else { return }
            self.sendTarget(id: id, target: target, snapshot: snapshot)
            self.movementTimer = Timer.scheduledTimer(withTimeInterval: DeskProtocol.targetWriteInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.sendTarget(id: id, target: target, snapshot: snapshot)
                }
            }
        }
    }

    private func sendTarget(id: UUID, target: Double, snapshot: OperationSnapshot) {
        guard id == requestGeneration,
              operation?.id == id,
              snapshotIsCurrent(snapshot),
              let peripheral,
              peripheral.identifier == snapshot.deskID,
              let inputCharacteristic,
              let outputCharacteristic,
              let startedAt = movementStartedAt
        else { return }

        if Date().timeIntervalSince(startedAt) > DeskProtocol.movementTimeout {
            failMovement("Desk movement exceeded 45 seconds and was stopped.")
            return
        }
        guard let raw = rawTarget(for: target, baseHeight: snapshot.configuration.baseHeight) else {
            failMovement("Target height cannot be represented by this desk controller.")
            return
        }
        let targetWriteType = writeType(for: inputCharacteristic)
        if targetWriteType == .withResponse {
            guard targetWriteInFlightGeneration == nil else {
                peripheral.readValue(for: outputCharacteristic)
                return
            }
            targetWriteInFlightGeneration = id
        }
        peripheral.writeValue(littleEndianData(raw), for: inputCharacteristic, type: targetWriteType)
        peripheral.readValue(for: outputCharacteristic)
    }

    private func evaluateMovement(
        _ reading: DeskReading,
        id: UUID,
        target: Double,
        snapshot: OperationSnapshot
    ) {
        guard id == requestGeneration,
              operation?.id == id,
              snapshotIsCurrent(snapshot)
        else { return }
        guard let startedAt = movementStartedAt else {
            beginMovement(id: id, target: target, snapshot: snapshot, reading: reading)
            return
        }
        if Date().timeIntervalSince(startedAt) > DeskProtocol.movementTimeout {
            failMovement("Desk movement exceeded 45 seconds and was stopped.")
            return
        }
        guard var evaluator = movementEvaluator else { return }
        let result = evaluator.evaluate(
            reading,
            previous: previousReading,
            elapsed: Date().timeIntervalSince(startedAt)
        )
        movementEvaluator = evaluator
        previousReading = reading

        switch result {
        case .moving:
            break
        case .reached:
            invalidateActiveOperation()
            startFinalStop()
        case .stalled:
            failMovement("The desk stopped before reaching the target. Check for an obstruction.")
        }
    }

    private func failMovement(_ message: String) {
        invalidateActiveOperation()
        pendingAfterStop = nil
        alertMessage = message
        startFinalStop()
    }

    private func startFinalStop() {
        movementTimer?.invalidate()
        movementTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        guard finalStopGeneration == nil else { return }
        guard let peripheral,
              peripheral.state == .connected,
              let controlCharacteristic
        else {
            finishFinalStop()
            return
        }

        beginMovementBackgroundTask()
        let stopID = UUID()
        finalStopGeneration = stopID
        connectionState = .stopping
        let writeType = writeType(for: controlCharacteristic)
        if writeType == .withResponse {
            pendingControlWrites = [
                QueuedControlWrite(data: DeskProtocol.stopPayload, purpose: .finalStop(stopID)),
            ]
            scheduleFinalStopTimeout(stopID: stopID, delay: 2)
            sendNextControlWriteIfNeeded()
        } else {
            peripheral.writeValue(DeskProtocol.stopPayload, for: controlCharacteristic, type: writeType)
            scheduleFinalStopTimeout(stopID: stopID, delay: 0.25)
        }
    }

    private func scheduleFinalStopTimeout(stopID: UUID, delay: TimeInterval) {
        finalStopTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard self?.finalStopGeneration == stopID else { return }
            let finalStopIsPending = self?.controlWriteInFlight?.purpose == .finalStop(stopID) ||
                self?.pendingControlWrites.contains(where: { $0.purpose == .finalStop(stopID) }) == true
            if finalStopIsPending {
                self?.failFinalStop("The desk did not acknowledge the Stop command.")
            } else {
                self?.finishFinalStop()
            }
        }
        finalStopTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }

    private func finishFinalStop() {
        finalStopTimeout?.cancel()
        finalStopTimeout = nil
        finalStopGeneration = nil
        endMovementBackgroundTask()
        if pendingMutation != nil {
            completeMutation()
            if operation != nil || finalStopGeneration != nil { return }
        }
        if let next = pendingAfterStop {
            pendingAfterStop = nil
            activate(next)
        } else {
            connectionState = peripheral?.state == .connected ? .connected : .disconnected
        }
    }

    private func failFinalStop(_ message: String) {
        if pendingMutation != nil {
            settingsMutationState = .failed(message)
        }
        pendingAfterStop = nil
        pendingMutation = nil
        finalStopTimeout?.cancel()
        finalStopTimeout = nil
        finalStopGeneration = nil
        pendingControlWrites = []
        controlWriteInFlight = nil
        endMovementBackgroundTask()
        disconnectCurrentDesk()
        connectionState = .disconnected
        alertMessage = "\(message) Stop was not confirmed. Use the physical controller before continuing."
    }

    private func failUnconfirmedStop(_ message: String) {
        invalidateActiveOperation()
        pendingAfterStop = nil
        finalStopTimeout?.cancel()
        finalStopTimeout = nil
        finalStopGeneration = nil
        pendingControlWrites = []
        controlWriteInFlight = nil
        endMovementBackgroundTask()
        disconnectCurrentDesk()
        connectionState = .disconnected
        alertMessage = "\(message) Stop was not confirmed. Use the physical controller before continuing."
    }

    private func writeControl(_ data: Data, purpose: ControlWrite) {
        guard let peripheral, let controlCharacteristic else { return }
        let type = writeType(for: controlCharacteristic)
        if type == .withResponse {
            pendingControlWrites.append(QueuedControlWrite(data: data, purpose: purpose))
            sendNextControlWriteIfNeeded()
        } else {
            peripheral.writeValue(data, for: controlCharacteristic, type: type)
        }
    }

    private func sendNextControlWriteIfNeeded() {
        guard controlWriteInFlight == nil,
              !pendingControlWrites.isEmpty,
              let peripheral,
              peripheral.state == .connected,
              let controlCharacteristic
        else { return }
        let write = pendingControlWrites.removeFirst()
        controlWriteInFlight = write
        if case let .finalStop(stopID) = write.purpose {
            scheduleFinalStopTimeout(stopID: stopID, delay: 1)
        }
        peripheral.writeValue(write.data, for: controlCharacteristic, type: .withResponse)
    }

    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    }

    private func beginMovementBackgroundTask() {
        guard movementBackgroundTask == .invalid else { return }
        movementBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Standing Desk Movement") { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.invalidateActiveOperation()
                self.pendingAfterStop = nil
                self.cancelPendingMutation("Settings change failed because background time expired.")
                self.bestEffortStop()
                self.finalStopTimeout?.cancel()
                self.finalStopTimeout = nil
                self.finalStopGeneration = nil
                self.pendingControlWrites = []
                self.controlWriteInFlight = nil
                self.connectionState = .disconnected
                self.alertMessage = "Background time expired. Stop was not confirmed. Use the physical controller before continuing."
                self.endMovementBackgroundTask()
            }
        }
    }

    private func endMovementBackgroundTask() {
        guard movementBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(movementBackgroundTask)
        movementBackgroundTask = .invalid
    }

    private func bestEffortStop() {
        guard let peripheral,
              peripheral.state == .connected,
              let controlCharacteristic
        else { return }
        peripheral.writeValue(
            DeskProtocol.stopPayload,
            for: controlCharacteristic,
            type: writeType(for: controlCharacteristic)
        )
    }

    private func handleBluetoothUnavailable(_ message: String) {
        let movementWasPending = hasQueuedOrActiveMovement ||
            operation?.kind == .stop ||
            movementBackgroundTask != .invalid
        scanRequested = false
        scanTimeout?.cancel()
        scanTimeout = nil
        if central.state == .poweredOn {
            central.stopScan()
        }
        invalidateActiveOperation()
        pendingAfterStop = nil
        cancelPendingMutation("Settings change failed because Bluetooth became unavailable.")
        finalStopTimeout?.cancel()
        finalStopTimeout = nil
        finalStopGeneration = nil
        pendingControlWrites = []
        controlWriteInFlight = nil
        endMovementBackgroundTask()
        disconnectCurrentDesk()
        connectionState = .bluetoothUnavailable(message)
        if movementWasPending {
            alertMessage = "\(message). Stop could not be confirmed. Use the physical controller before continuing."
        }
    }

    private func addDiscoveredDesk(_ peripheral: CBPeripheral, rssi: Int, connected: Bool, advertisedName: String? = nil) {
        let desk = DiscoveredDesk(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name ?? "Desk",
            rssi: rssi,
            isConnected: connected
        )
        if let index = discoveredDesks.firstIndex(where: { $0.id == desk.id }) {
            discoveredDesks[index] = desk
        } else {
            discoveredDesks.append(desk)
        }
        discoveredDesks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fail(_ message: String) {
        if operation?.kind == .stop {
            failUnconfirmedStop(message)
            return
        }
        let wasMovement = hasQueuedOrActiveMovement
        invalidateActiveOperation()
        pendingAfterStop = nil
        connectionTimeout?.cancel()
        alertMessage = message
        if wasMovement {
            startFinalStop()
        } else {
            connectionState = peripheral?.state == .connected ? .connected : .disconnected
        }
    }
}

extension DeskBluetoothController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if scanRequested {
                beginScan()
            } else if let operation, operation.id == requestGeneration {
                connectSelectedDesk(for: operation)
            } else {
                connectionState = peripheral?.state == .connected ? .connected : .disconnected
            }
        case .unknown:
            if movementStartedAt != nil || finalStopGeneration != nil {
                handleBluetoothUnavailable("Bluetooth is unavailable")
            } else if scanRequested {
                connectionState = .scanning
            } else if operation != nil {
                connectionState = .connecting
            } else {
                connectionState = .bluetoothUnavailable("Bluetooth is unavailable")
            }
        case .unauthorized, .poweredOff, .unsupported, .resetting:
            scanRequested = false
            handleBluetoothUnavailable(bluetoothUnavailableMessage(for: central.state))
        @unknown default:
            handleBluetoothUnavailable("Bluetooth state is unsupported")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard isDiscoveryCandidate(
            peripheralName: peripheral.name,
            advertisedName: advertisedName,
            advertisedServices: services,
            nameFilter: settingsStore.settings.configuration.deskName
        ) else { return }
        addDiscoveredDesk(
            peripheral,
            rssi: RSSI.intValue,
            connected: peripheral.state == .connected,
            advertisedName: advertisedName
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect connectedPeripheral: CBPeripheral) {
        guard connectedPeripheral === peripheral,
              let operation,
              operation.id == requestGeneration,
              snapshotIsCurrent(operation.snapshot),
              connectedPeripheral.identifier == operation.snapshot.deskID
        else {
            central.cancelPeripheralConnection(connectedPeripheral)
            return
        }
        prepareConnectedDesk(connectedPeripheral, for: operation)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect failedPeripheral: CBPeripheral, error: Error?) {
        guard failedPeripheral === peripheral else { return }
        clearConnectionResources()
        guard operation?.id == requestGeneration else {
            if scanRequested { connectionState = .scanning }
            return
        }
        let message = "Could not connect to the desk: \(error?.localizedDescription ?? "unknown error")."
        if operation?.kind == .stop {
            failUnconfirmedStop(message)
        } else {
            fail(message)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral disconnectedPeripheral: CBPeripheral, error: Error?) {
        guard disconnectedPeripheral === peripheral else { return }
        clearConnectionResources()
        if finalStopGeneration != nil {
            failFinalStop("The desk disconnected before it acknowledged Stop.")
        } else if let operation {
            switch operation.kind {
            case .move:
                failUnconfirmedStop("The desk disconnected during movement.")
            case .stop:
                failUnconfirmedStop("The desk disconnected before Stop could be sent.")
            case .status:
                fail("The desk disconnected while reading its height.")
            }
        } else if pendingAfterStop?.isMovement == true {
            failUnconfirmedStop("The desk disconnected before the next movement request could start safely.")
        } else if scanRequested {
            connectionState = .scanning
        } else {
            connectionState = .disconnected
        }
    }
}

extension DeskBluetoothController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ callbackPeripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard callbackIsCurrent(callbackPeripheral) else { return }
        if let error {
            fail("Could not discover desk services: \(error.localizedDescription).")
            return
        }
        for service in callbackPeripheral.services ?? [] {
            switch service.uuid {
            case DeskProtocol.controlServiceUUID:
                callbackPeripheral.discoverCharacteristics([DeskProtocol.controlCharacteristicUUID], for: service)
            case DeskProtocol.outputServiceUUID:
                callbackPeripheral.discoverCharacteristics([DeskProtocol.outputCharacteristicUUID], for: service)
            case DeskProtocol.inputServiceUUID:
                callbackPeripheral.discoverCharacteristics([DeskProtocol.inputCharacteristicUUID], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ callbackPeripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard callbackIsCurrent(callbackPeripheral) else { return }
        if let error {
            fail("Could not discover desk controls: \(error.localizedDescription).")
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case DeskProtocol.controlCharacteristicUUID:
                controlCharacteristic = characteristic
            case DeskProtocol.outputCharacteristicUUID:
                outputCharacteristic = characteristic
            case DeskProtocol.inputCharacteristicUUID:
                inputCharacteristic = characteristic
            default:
                break
            }
        }
        startOperationWhenReady()
    }

    func peripheral(_ callbackPeripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard callbackIsCurrent(callbackPeripheral), characteristic == outputCharacteristic else { return }
        if let error {
            fail("Could not read desk height: \(error.localizedDescription).")
            return
        }
        guard let operation,
              operation.id == requestGeneration,
              let data = characteristic.value,
              let reading = decodeReading(data, baseHeight: operation.snapshot.configuration.baseHeight)
        else { return }

        initialReadingTimeout?.cancel()
        initialReadingTimeout = nil

        currentHeight = reading.heightCm
        currentSpeed = reading.speed
        switch operation {
        case .status:
            invalidateActiveOperation()
            connectionState = .connected
        case let .move(id, target, snapshot):
            evaluateMovement(reading, id: id, target: target, snapshot: snapshot)
        case .stop:
            break
        }
    }

    func peripheral(_ callbackPeripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if callbackPeripheral === peripheral,
           characteristic == inputCharacteristic,
           let writeGeneration = targetWriteInFlightGeneration
        {
            targetWriteInFlightGeneration = nil
            if writeGeneration == requestGeneration,
               operation?.id == writeGeneration,
               let error
            {
                failMovement("The desk rejected the target height: \(error.localizedDescription).")
            }
            return
        }
        guard callbackPeripheral === peripheral,
              characteristic == controlCharacteristic,
              let queuedWrite = controlWriteInFlight
        else { return }
        controlWriteInFlight = nil
        let write = queuedWrite.purpose
        switch write {
        case let .setup(id):
            if id == requestGeneration, operation?.id == id, let error {
                failMovement("The desk rejected a movement command: \(error.localizedDescription).")
            } else if id == requestGeneration,
                      operation?.id == id,
                      !pendingControlWrites.contains(where: { $0.purpose == .setup(id) })
            {
                if case let .move(_, target, snapshot) = operation {
                    scheduleMovementTargetWrites(id: id, target: target, snapshot: snapshot)
                }
            }
        case let .finalStop(id):
            if id == finalStopGeneration {
                if let error {
                    failFinalStop("The desk rejected the Stop command: \(error.localizedDescription).")
                } else {
                    finishFinalStop()
                }
            }
        }
        sendNextControlWriteIfNeeded()
    }

    private func callbackIsCurrent(_ callbackPeripheral: CBPeripheral) -> Bool {
        guard callbackPeripheral === peripheral,
              let operation,
              operation.id == requestGeneration,
              snapshotIsCurrent(operation.snapshot),
              callbackPeripheral.identifier == operation.snapshot.deskID
        else { return false }
        return true
    }
}
