import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState

    private let cameraController: CameraControlling?
    private let gestureResetter: GestureResetting?
    private let inputController: InputControlling?

    private let cameraService: CameraService?
    private let trackingService: TrackingService?
    private let gesturePipeline: GesturePipeline?
    private let concreteInputController: MacOSInputController?
    private let permissionService: PermissionStatusService?
    private let settingsStore: SettingsStore?
    private let calibrationViewModel: CalibrationViewModel?
    private let uiModel: SignalUIModel?
    private let launchAtLoginViewModel: LaunchAtLoginViewModel?
    private let lifecycleMonitor: AppLifecycleMonitor?
    private let emergencyMonitor: EmergencyShortcutMonitor?
    private weak var previewLayerController: CameraPreviewLayerController?

    private var cancellables: Set<AnyCancellable> = []
    private var permissions = PermissionSnapshot(
        camera: .unknown,
        accessibilityTrusted: false
    )
    private var emergencyHealth = EmergencyMonitorHealth(
        globalMonitorInstalled: false,
        localMonitorInstalled: false
    )
    private var cameraState: CameraServiceState = .stopped
    private var cameraStateRevision: UInt64 = 0
    private var latestTrackingQuality: TrackingQuality = .absent
    private var cameraStartRequested = false
    private var inputEnableRequested = false
    private var sessionIsActive = true
    private var runtimeStarted = false
    private var suddenTerminationIsDisabled = false
    private var calibrationMetrics = CalibrationMetricAccumulator()
    private let trackingWatchdog: TrackingLossWatchdog
    private let trackingDelivery = LatestOnlyMainActorDelivery<TrackingDelivery>()
    private let safetyEnableLease = SafetyEnableLease()
    private var activeEnableToken: SafetyEnableLease.Token?
    private var producerSafetyFence: ProducerSafetyFence?

    /// Test/support initializer. The ordering here is deliberately the same
    /// safety fence used by the production composition.
    init(
        state: AppState,
        cameraController: CameraControlling? = nil,
        gestureResetter: GestureResetting? = nil,
        inputController: InputControlling? = nil,
        trackingWatchdog: TrackingLossWatchdog = TrackingLossWatchdog(),
        initialPermissions: PermissionSnapshot = PermissionSnapshot(
            camera: .unknown,
            accessibilityTrusted: false
        ),
        initialEmergencyHealth: EmergencyMonitorHealth = EmergencyMonitorHealth(
            globalMonitorInstalled: false,
            localMonitorInstalled: false
        )
    ) {
        self.state = state
        self.trackingWatchdog = trackingWatchdog
        permissions = initialPermissions
        emergencyHealth = initialEmergencyHealth
        self.cameraController = cameraController
        self.gestureResetter = gestureResetter
        self.inputController = inputController
        cameraService = cameraController as? CameraService
        trackingService = nil
        gesturePipeline = gestureResetter as? GesturePipeline
        concreteInputController = inputController as? MacOSInputController
        permissionService = nil
        settingsStore = nil
        calibrationViewModel = nil
        uiModel = nil
        launchAtLoginViewModel = nil
        lifecycleMonitor = nil
        emergencyMonitor = nil
        if let input = inputController as? MacOSInputController {
            let delivery = trackingDelivery
            producerSafetyFence = ProducerSafetyFence(
                lease: safetyEnableLease,
                invalidateDeliveries: { delivery.invalidate() },
                releaseInput: { [weak input] in input?.releaseAllInputs() }
            )
        }

        inputController?.setOutputGate(enabled: false)
    }

    /// Production composition initializer. Construction never prompts and
    /// never restores output; startRuntime() installs passive observers only.
    init(
        state: AppState,
        uiModel: SignalUIModel,
        settingsStore: SettingsStore,
        calibrationViewModel: CalibrationViewModel,
        cameraService: CameraService,
        trackingService: TrackingService,
        gesturePipeline: GesturePipeline,
        inputController: MacOSInputController,
        permissionService: PermissionStatusService,
        launchAtLoginViewModel: LaunchAtLoginViewModel,
        lifecycleMonitor: AppLifecycleMonitor,
        emergencyMonitor: EmergencyShortcutMonitor,
        trackingWatchdog: TrackingLossWatchdog = TrackingLossWatchdog()
    ) {
        self.state = state
        self.trackingWatchdog = trackingWatchdog
        self.uiModel = uiModel
        self.settingsStore = settingsStore
        self.calibrationViewModel = calibrationViewModel
        self.cameraService = cameraService
        self.cameraController = cameraService
        self.trackingService = trackingService
        self.gesturePipeline = gesturePipeline
        self.gestureResetter = gesturePipeline
        self.concreteInputController = inputController
        self.inputController = inputController
        self.permissionService = permissionService
        self.launchAtLoginViewModel = launchAtLoginViewModel
        self.lifecycleMonitor = lifecycleMonitor
        self.emergencyMonitor = emergencyMonitor

        let delivery = trackingDelivery
        producerSafetyFence = ProducerSafetyFence(
            lease: safetyEnableLease,
            invalidateDeliveries: { delivery.invalidate() },
            releaseInput: { [weak inputController] in inputController?.releaseAllInputs() }
        )
    }

    func startRuntime() {
        guard !runtimeStarted else { return }
        runtimeStarted = true
        installCallbacks()
        observeSettings()
        inputController?.setOutputGate(enabled: false)
        permissions = permissionService?.currentSnapshot() ?? permissions
        if let initialCameraUpdate = cameraService?.stateUpdate {
            cameraState = initialCameraUpdate.state
            cameraStateRevision = initialCameraUpdate.revision
        }
        lifecycleMonitor?.start()
        if let emergencyMonitor {
            emergencyHealth = emergencyMonitor.start()
        }
        refreshExternalStatus(refreshEmergencyMonitor: false)
    }

    func setPreviewLayerController(_ controller: CameraPreviewLayerController) {
        previewLayerController = controller
    }

    func makeActions(
        openCalibrationWindow: @escaping @MainActor () -> Void,
        openSettingsWindow: @escaping @MainActor () -> Void
    ) -> SignalUIActions {
        SignalUIActions(
            enableControl: { [weak self] in self?.enableControl() },
            disableControl: { [weak self] in self?.quiesce(reason: .userDisabled) },
            pauseControl: { [weak self] in self?.quiesce(reason: .paused) },
            resumeControl: { [weak self] in self?.enableControl() },
            openCalibration: { [weak self] in
                self?.calibrationDidOpen()
                openCalibrationWindow()
            },
            closeCalibration: { [weak self] in self?.calibrationDidClose() },
            openSettings: openSettingsWindow,
            requestCameraPermission: { [weak self] in self?.requestCameraPermission() },
            requestAccessibilityPermission: { [weak self] in
                self?.requestAccessibilityPermission()
            },
            retryCamera: { [weak self] in self?.retryCalibrationCamera() },
            emergencyStop: { [weak self] in self?.emergencyStopFromMenu() },
            quit: { [weak self] in self?.quit() }
        )
    }

    func enableControl() {
        safetyEnableLease.revoke()
        activeEnableToken = nil
        if let refreshed = permissionService?.refresh() {
            handlePermissions(refreshed)
        }
        guard permissions.cameraAuthorized else {
            apply(controlIntent: .disabled, status: .cameraPermissionMissing)
            return
        }
        guard permissions.accessibilityTrusted else {
            apply(controlIntent: .disabled, status: .accessibilityPermissionMissing)
            return
        }
        guard emergencyHealth.permitsEnable(accessibilityTrusted: true) else {
            apply(controlIntent: .disabled, status: .emergencyStopped)
            return
        }
        guard sessionIsActive else {
            apply(controlIntent: .disabled, status: .disabled)
            return
        }

        inputController?.setOutputGate(enabled: false)
        inputEnableRequested = false
        activeEnableToken = safetyEnableLease.issue()
        apply(controlIntent: .enabled, status: .waitingForHand)
        armFirstSnapshotIfCameraRunning()
        reconcileCameraDemand()
    }

    func calibrationDidOpen() {
        state.setCalibrationOpen(true)
        publishUI()
        reconcileCameraDemand()
    }

    func calibrationDidClose() {
        state.setCalibrationOpen(false)
        calibrationViewModel?.clear()
        calibrationMetrics.reset()
        if state.controlIntent != .enabled {
            trackingService?.reset(reason: .extendedGap)
            gestureResetter?.reset(reason: .cameraStopped)
        }
        publishUI()
        reconcileCameraDemand()
    }

    func quiesce(reason: SafetyStopReason, resetGesture: Bool = true) {
        safetyEnableLease.revoke()
        activeEnableToken = nil
        trackingWatchdog.disarm()
        trackingDelivery.invalidate()
        inputEnableRequested = false
        latestTrackingQuality = .absent
        inputController?.setOutputGate(enabled: false)
        let terminalEvents = resetGesture
            ? (gestureResetter?.reset(reason: gestureResetReason(for: reason)) ?? [])
            : []
        terminalEvents.forEach { inputController?.handle($0) }
        inputController?.releaseAllInputs()
        trackingService?.reset(reason: trackingResetReason(for: reason))
        calibrationMetrics.reset()
        restoreSuddenTerminationIfNeeded()

        if !state.calibrationIsOpen {
            cameraStartRequested = false
            cameraController?.stop()
        }

        apply(
            controlIntent: reason == .paused ? .paused : .disabled,
            status: status(for: reason)
        )
    }

    private func installCallbacks() {
        let watchdog = trackingWatchdog
        let concreteInputController = concreteInputController
        let cameraService = cameraService
        let safetyFence = producerSafetyFence
        trackingWatchdog.onFire = { [weak self, weak gesturePipeline,
                                     weak cameraService] timestamp, generation in
            safetyFence?.revoke(for: .watchdog)
            _ = gesturePipeline?.advance(to: timestamp, forwardNormalOutput: false)
            Task { @MainActor [weak self, weak cameraService] in
                guard let self,
                      generation == 0 || cameraService?.isGenerationCurrent(generation) != false else { return }
                self.handleWatchdogTrackingLoss()
            }
        }
        let trackingDelivery = trackingDelivery
        trackingService?.onSnapshot = { [weak gesturePipeline] snapshot in
            guard let gesturePipeline else { return }
            let gesture = gesturePipeline.process(snapshot)
            if gesture.events.contains(.trackingLost) {
                safetyFence?.revoke(for: .trackingLost)
            }
            if snapshot.degradationReason == .visionFailure {
                watchdog.disarm()
                safetyFence?.revoke(for: .trackingLost)
                // Terminal tracking failures cannot use the replaceable
                // diagnostics lane: a following good/no-hand snapshot could
                // otherwise coalesce this quiesce away after the producer
                // fence has already revoked the enable lease.
                trackingDelivery.submitUncoalesced(
                    TrackingDelivery(snapshot: snapshot, gesture: gesture)
                ) { [weak self] delivery in
                    self?.handleTracking(snapshot: delivery.snapshot, gesture: delivery.gesture)
                }
                return
            } else {
                // Every accepted result proves capture/processing liveness.
                // Recognition quality is deliberately not a camera watchdog:
                // an empty frame must not stop a healthy running session.
                watchdog.arm(
                    snapshot: snapshot,
                    grace: gesturePipeline.trackingLossGraceDuration
                )
            }
            trackingDelivery.submit(TrackingDelivery(snapshot: snapshot, gesture: gesture)) {
                [weak self] delivery in
                self?.handleTracking(snapshot: delivery.snapshot, gesture: delivery.gesture)
            }
        }
        cameraService?.onDiagnostics = { [weak trackingService] diagnostics in
            trackingService?.updateCameraDiagnostics(
                captureFPS: diagnostics.captureFPS,
                droppedFrames: diagnostics.drops.total
            )
        }
        cameraService?.onStateUpdate = { [weak self] update in
            if update.state.isTerminalForInput {
                watchdog.disarm()
                safetyFence?.revoke(for: .cameraTerminal)
            }
            Task { @MainActor [weak self] in self?.handleCameraState(update) }
        }
        permissionService?.onChange = { [weak self] snapshot in
            if !snapshot.cameraAuthorized || !snapshot.accessibilityTrusted {
                watchdog.disarm()
                safetyFence?.revoke(for: .permissionLost)
            }
            Task { @MainActor [weak self] in self?.handlePermissions(snapshot) }
        }
        concreteInputController?.onFault = { [weak self] fault in
            safetyFence?.revoke(for: .inputFault)
            Task { @MainActor [weak self] in self?.handleInputFault(fault) }
        }
        lifecycleMonitor?.onSafetyStop = { [weak self] reason in
            watchdog.disarm()
            safetyFence?.revoke(for: .lifecycle)
            Task { @MainActor [weak self] in self?.handleLifecycleStop(reason) }
        }
        lifecycleMonitor?.onSignal = { [weak self] signal in
            guard signal.requestsStatusRefresh else { return }
            Task { @MainActor [weak self] in self?.handleLifecycleRecovery(signal) }
        }
        emergencyMonitor?.onEmergency = { [weak self] in
            watchdog.disarm()
            safetyFence?.revoke(for: .emergency)
            Task { @MainActor [weak self] in self?.quiesce(reason: .emergency) }
        }
        emergencyMonitor?.onHealthChange = { [weak self] health in
            if !health.globalMonitorInstalled || !health.localMonitorInstalled {
                safetyFence?.revoke(for: .emergencyMonitorUnhealthy)
            }
            Task { @MainActor [weak self] in self?.handleEmergencyHealth(health) }
        }
    }

    private func observeSettings() {
        guard let settingsStore else { return }
        settingsStore.$configurationRevision
            .dropFirst()
            .sink { [weak self, weak settingsStore] _ in
                Task { @MainActor [weak self] in
                    guard let settingsStore else { return }
                    self?.applySettingsConfiguration(
                        tuning: settingsStore.tuning,
                        profiles: settingsStore.zoomProfiles,
                        screenZoomShortcutsEnabled: settingsStore.screenZoomShortcutsEnabled
                    )
                }
            }
            .store(in: &cancellables)
    }

    func handleTracking(
        snapshot: TrackingSnapshot,
        gesture: GestureFrameResult
    ) {
        guard snapshot.captureGeneration == 0
                || cameraService?.isGenerationCurrent(snapshot.captureGeneration) != false else {
            return
        }
        latestTrackingQuality = snapshot.quality
        if state.calibrationIsOpen {
            calibrationViewModel?.submit(
                tracking: snapshot,
                gesture: gesture,
                input: calibrationMetrics.consume(
                    tracking: snapshot,
                    events: gesture.events,
                    zoomEpisode: gesture.zoomEpisode,
                    zoomDistance: gesture.diagnostics.zoomDistance
                ),
                permissions: PermissionDiagnosticSnapshot(
                    cameraAuthorized: permissions.cameraAuthorized,
                    accessibilityTrusted: permissions.accessibilityTrusted
                ),
                inputEnabled: concreteInputController?.isOutputEnabled ?? false
            )
        }

        guard state.controlIntent == .enabled else { return }
        if snapshot.degradationReason == .visionFailure {
            quiesce(reason: .trackingLost)
            return
        }
        if gesture.events.contains(.trackingLost) {
            quiesce(reason: .trackingLost)
            return
        }
        let recognitionUnavailable = snapshot.quality != .good
            || gesture.diagnostics.pointerSuppressionReason == .trackingUnavailable
            || gesture.diagnostics.pointerSuppressionReason == .multipleHands
            || gesture.diagnostics.pointerSuppressionReason == .poseMismatch
        guard !recognitionUnavailable else {
            // No hand, ambiguous association, and temporarily missing anchors
            // are neutral recognition states. GesturePipeline already
            // synchronously suspends owned output; keep the explicit session
            // alive and wait for one reliable hand to return.
            apply(controlIntent: .enabled, status: .waitingForHand)
            return
        }
        evaluateOutputEligibility()
    }

    private func evaluateOutputEligibility() {
        guard let enableToken = activeEnableToken,
              safetyEnableLease.isValid(enableToken) else {
            inputEnableRequested = false
            inputController?.setOutputGate(enabled: false)
            return
        }
        let cameraRunning: Bool
        if case .running = cameraState {
            cameraRunning = true
        } else {
            cameraRunning = false
        }
        let eligible = state.controlIntent == .enabled
            && permissions.cameraAuthorized
            && permissions.accessibilityTrusted
            && emergencyHealth.permitsEnable(accessibilityTrusted: true)
            && sessionIsActive
            && cameraRunning
            && latestTrackingQuality == .good
        guard eligible else { return }

        if concreteInputController?.isOutputEnabled == true {
            inputEnableRequested = false
            disableSuddenTerminationIfNeeded()
            apply(controlIntent: .enabled, status: .enabled)
        } else if !inputEnableRequested {
            let didBegin = safetyEnableLease.withValid(enableToken) { [self] in
                // Input enable begins while holding the lease lock. A producer
                // revocation therefore orders either wholly before this call,
                // or after it and immediately disables the new gate generation.
                disableSuddenTerminationIfNeeded()
                inputController?.setOutputGate(enabled: true)
                return true
            } ?? false
            inputEnableRequested = didBegin
        }
    }

    func handleCameraState(_ update: CameraStateUpdate) {
        guard update.revision > cameraStateRevision else { return }
        cameraStateRevision = update.revision
        let nextState = update.state
        cameraState = nextState
        switch nextState {
        case let .running(generation, _):
            cameraStartRequested = true
            if state.controlIntent == .enabled {
                trackingWatchdog.armWaitingForFirstSnapshot(
                    captureGeneration: generation
                )
            }
            previewLayerController?.refreshConnectionConfiguration()
        case .starting, .stopping:
            break
        case .stopped:
            cameraStartRequested = false
            if state.controlIntent == .enabled {
                quiesce(reason: .cameraStopped)
            } else if state.calibrationIsOpen {
                reconcileCameraDemand()
            }
        case .permissionRequired:
            cameraStartRequested = false
            if state.controlIntent == .enabled {
                quiesce(reason: .cameraPermissionLost)
            } else {
                apply(controlIntent: .disabled, status: .cameraPermissionMissing)
            }
        case .interrupted:
            cameraStartRequested = false
            if state.controlIntent == .enabled { quiesce(reason: .cameraInterrupted) }
        case .unavailable, .failed:
            cameraStartRequested = false
            if state.controlIntent == .enabled {
                quiesce(reason: .cameraFailed)
            } else {
                apply(controlIntent: .disabled, status: .cameraUnavailable)
            }
        }
    }

    private func handlePermissions(_ snapshot: PermissionSnapshot) {
        let previous = permissions
        permissions = snapshot
        if snapshot.camera != previous.camera {
            cameraService?.authorizationDidChange()
        }
        if previous.cameraAuthorized, !snapshot.cameraAuthorized {
            quiesce(reason: .cameraPermissionLost)
            return
        }
        if previous.accessibilityTrusted, !snapshot.accessibilityTrusted {
            quiesce(reason: .accessibilityPermissionLost)
            return
        }
        if state.controlIntent != .enabled {
            let nextStatus: AppStatus
            if !snapshot.cameraAuthorized {
                nextStatus = .cameraPermissionMissing
            } else if !snapshot.accessibilityTrusted {
                nextStatus = .accessibilityPermissionMissing
            } else if state.controlIntent == .paused {
                nextStatus = .paused
            } else {
                nextStatus = .disabled
            }
            apply(controlIntent: state.controlIntent, status: nextStatus)
        } else {
            publishUI()
        }
        if state.calibrationIsOpen { reconcileCameraDemand() }
    }

    private func handleInputFault(_ fault: InputControllerFault) {
        if fault == .accessibilityUnavailable {
            if let refreshed = permissionService?.refresh() {
                handlePermissions(refreshed)
            }
            quiesce(reason: .accessibilityPermissionLost)
            return
        }
        quiesceInputAndGestures(reason: .cameraStopped)
        cameraStartRequested = false
        if !state.calibrationIsOpen { cameraController?.stop() }
        apply(controlIntent: .disabled, status: .error("Input unavailable: \(fault)"))
    }

    private func handleLifecycleStop(_ reason: SafetyStopReason) {
        switch reason {
        case .sleep, .sessionInactive, .shutdown:
            sessionIsActive = false
        case .displayConfigurationChanged, .userDisabled, .paused, .emergency,
             .trackingLost, .cameraStopped, .cameraInterrupted, .cameraFailed,
             .cameraPermissionLost, .accessibilityPermissionLost:
            break
        }
        if reason == .displayConfigurationChanged {
            concreteInputController?.displayConfigurationDidChange()
        }
        quiesce(reason: reason)
    }

    private func handleLifecycleRecovery(_ signal: AppLifecycleSignal) {
        if signal != .applicationDidBecomeActive {
            sessionIsActive = true
        }
        refreshExternalStatus()
        // Ordinary activation is a status reconciliation, not an implicit
        // control-state transition. Wake/session recovery remains disabled
        // after the synchronous safety stop and needs explicit Enable.
        reconcileCameraDemand()
    }

    private func handleEmergencyHealth(_ health: EmergencyMonitorHealth) {
        emergencyHealth = health
        if state.controlIntent == .enabled,
           !health.permitsEnable(accessibilityTrusted: permissions.accessibilityTrusted) {
            quiesce(reason: .emergency)
        }
    }

    func applySettingsConfiguration(
        tuning storedTuning: GestureTuning,
        profiles: [ZoomApplicationProfileSetting],
        screenZoomShortcutsEnabled: Bool = false
    ) {
        quiesceForSettingsChange()
        let tuning = runtimeTuning(storedTuning)
        trackingService?.update(tuning: tuning)
        gesturePipeline?.update(tuning: tuning)
        concreteInputController?.updateConfiguration(
            tuning: tuning,
            // Per-application shortcuts can change browser page zoom. Keep
            // production output locked to the standard screen-zoom profile.
            zoomProfiles: ZoomOutputPolicy.productionProfiles(ignoring: profiles),
            screenZoomShortcutsEnabled: screenZoomShortcutsEnabled
        )
    }

    private func quiesceForSettingsChange() {
        safetyEnableLease.revoke()
        activeEnableToken = nil
        inputEnableRequested = false
        inputController?.setOutputGate(enabled: false)
        let terminal = gestureResetter?.reset(reason: .settingsChanged) ?? []
        terminal.forEach { inputController?.handle($0) }
        inputController?.releaseAllInputs()
        trackingService?.reset(reason: .extendedGap)
        calibrationMetrics.reset()
        restoreSuddenTerminationIfNeeded()
        if !state.calibrationIsOpen {
            cameraStartRequested = false
            cameraController?.stop()
        }
        apply(controlIntent: .disabled, status: .disabled)
    }

    private func runtimeTuning(_ stored: GestureTuning) -> GestureTuning {
        stored.validated()
    }

    private func reconcileCameraDemand() {
        let desired = permissions.cameraAuthorized
            && sessionIsActive
            && (state.controlIntent == .enabled || state.calibrationIsOpen)
        if desired, !cameraStartRequested {
            cameraStartRequested = true
            cameraController?.start()
        } else if !desired, cameraStartRequested {
            cameraStartRequested = false
            cameraController?.stop()
        }
    }

    private func armFirstSnapshotIfCameraRunning() {
        guard state.controlIntent == .enabled,
              case let .running(generation, _) = cameraState else { return }
        trackingWatchdog.armWaitingForFirstSnapshot(captureGeneration: generation)
    }

    private func refreshExternalStatus(refreshEmergencyMonitor: Bool = true) {
        if refreshEmergencyMonitor, let emergencyMonitor {
            emergencyHealth = emergencyMonitor.start()
        }
        if let refreshed = permissionService?.refresh() {
            handlePermissions(refreshed)
        }
        launchAtLoginViewModel?.refresh()
        publishUI()
    }

    private func requestCameraPermission() {
        permissionService?.requestCameraAccess { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let refreshed = self.permissionService?.refresh() {
                    self.handlePermissions(refreshed)
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        permissionService?.promptForAccessibility()
        if let refreshed = permissionService?.refresh() {
            handlePermissions(refreshed)
            guard !refreshed.accessibilityTrusted else { return }
        }
        // AXIsProcessTrustedWithOptions only presents its prompt once for some
        // TCC identities. A later explicit button press still opens System
        // Settings through public workspace APIs; the UI explains the manual
        // Privacy & Security > Accessibility navigation path.
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func retryCalibrationCamera() {
        guard state.calibrationIsOpen, permissions.cameraAuthorized else { return }
        cameraStartRequested = false
        reconcileCameraDemand()
    }

    private func emergencyStopFromMenu() {
        if let emergencyMonitor {
            emergencyMonitor.triggerFromMenu()
        } else {
            quiesce(reason: .emergency)
        }
    }

    private func quit() {
        quiesce(reason: .shutdown)
        lifecycleMonitor?.stop()
        emergencyMonitor?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func quiesceInputAndGestures(reason: GestureResetReason) {
        safetyEnableLease.revoke()
        activeEnableToken = nil
        trackingWatchdog.disarm()
        trackingDelivery.invalidate()
        inputEnableRequested = false
        inputController?.setOutputGate(enabled: false)
        let terminal = gestureResetter?.reset(reason: reason) ?? []
        terminal.forEach { inputController?.handle($0) }
        inputController?.releaseAllInputs()
        restoreSuddenTerminationIfNeeded()
    }

    private func apply(controlIntent: ControlIntent, status: AppStatus) {
        state.apply(controlIntent: controlIntent, status: status)
        publishUI()
    }

    private func publishUI() {
        uiModel?.apply(
            controlIntent: state.controlIntent,
            status: state.status,
            cameraAuthorized: permissions.cameraAuthorized,
            cameraPermission: permissions.camera,
            accessibilityTrusted: permissions.accessibilityTrusted,
            calibrationIsOpen: state.calibrationIsOpen
        )
    }

    private func disableSuddenTerminationIfNeeded() {
        guard !suddenTerminationIsDisabled else { return }
        ProcessInfo.processInfo.disableSuddenTermination()
        suddenTerminationIsDisabled = true
    }

    private func restoreSuddenTerminationIfNeeded() {
        guard suddenTerminationIsDisabled else { return }
        ProcessInfo.processInfo.enableSuddenTermination()
        suddenTerminationIsDisabled = false
    }

    private func handleWatchdogTrackingLoss() {
        guard state.controlIntent == .enabled else { return }
        // Producer-side advance may have used the startup watchdog's synthetic
        // uptime before any camera timestamp existed. Reset again on the main
        // actor so an explicit re-enable/new generation can establish its own
        // valid timestamp origin. trackingLost emission is idempotent.
        quiesce(reason: .trackingLost, resetGesture: true)
    }

    private func gestureResetReason(for reason: SafetyStopReason) -> GestureResetReason {
        switch reason {
        case .userDisabled: .disabled
        case .paused: .paused
        case .emergency: .emergency
        case .trackingLost: .trackingLost
        case .cameraStopped, .cameraInterrupted, .cameraFailed: .cameraStopped
        case .cameraPermissionLost, .accessibilityPermissionLost: .permissionLost
        case .sleep, .sessionInactive: .sessionInactive
        case .displayConfigurationChanged: .displayConfigurationChanged
        case .shutdown: .shutdown
        }
    }

    private func trackingResetReason(for reason: SafetyStopReason) -> TrackingResetReason {
        switch reason {
        case .cameraInterrupted, .cameraFailed: .interruption
        case .cameraPermissionLost, .accessibilityPermissionLost: .permissionLost
        case .shutdown: .shutdown
        case .userDisabled, .paused, .emergency, .trackingLost, .cameraStopped,
             .sleep, .sessionInactive, .displayConfigurationChanged:
            .cameraStopped
        }
    }

    private func status(for reason: SafetyStopReason) -> AppStatus {
        switch reason {
        case .paused: .paused
        case .emergency: .emergencyStopped
        case .trackingLost: .trackingDegraded
        case .cameraPermissionLost: .cameraPermissionMissing
        case .accessibilityPermissionLost: .accessibilityPermissionMissing
        case .cameraInterrupted, .cameraFailed: .cameraUnavailable
        case .userDisabled, .cameraStopped, .sleep, .sessionInactive,
             .displayConfigurationChanged, .shutdown:
            .disabled
        }
    }
}

struct ZoomEpisodeAccumulator {
    private var activeHandIDs: [HandTrackID]?
    private(set) var value = 0.0

    mutating func reset() {
        activeHandIDs = nil
        value = 0
    }

    mutating func consume(
        delta: Double,
        episode: ZoomEpisodeDiagnostic
    ) -> Double {
        guard episode.phase == .active, episode.handIDs.count == 1 else {
            reset()
            return value
        }
        let handIDs = episode.handIDs.sorted()
        if activeHandIDs != handIDs {
            reset()
            activeHandIDs = handIDs
        }
        if delta.isFinite {
            value += delta
        }
        return value
    }
}

private struct CalibrationMetricAccumulator {
    private var previousRaw: [HandTrackID: Point2D] = [:]
    private var previousFiltered: [HandTrackID: Point2D] = [:]
    private var zoomAccumulator = ZoomEpisodeAccumulator()

    mutating func reset() {
        previousRaw.removeAll(keepingCapacity: true)
        previousFiltered.removeAll(keepingCapacity: true)
        zoomAccumulator.reset()
    }

    mutating func consume(
        tracking: TrackingSnapshot,
        events: [GestureEvent],
        zoomEpisode: ZoomEpisodeDiagnostic,
        zoomDistance: Double?
    ) -> InputDiagnosticSnapshot {
        let hand = tracking.hands.sorted { $0.id < $1.id }.first
        let raw = hand?.rawLandmarks[.indexTip]?.position
        let filtered = hand?.filteredLandmarks[.indexTip]?.position
        let rawMovement = movement(from: hand.flatMap { previousRaw[$0.id] }, to: raw)
        let filteredMovement = movement(from: hand.flatMap { previousFiltered[$0.id] }, to: filtered)
        let normalizedMovement: Double? = {
            guard let rawMovement, let palm = hand?.palmWidth,
                  palm.isFinite, palm > 0 else { return nil }
            return rawMovement / palm
        }()
        if let hand, let raw { previousRaw = [hand.id: raw] }
        if let hand, let filtered { previousFiltered = [hand.id: filtered] }

        var pointer = Point2D.zero
        var hasPointer = false
        var scroll = Point2D.zero
        var hasScroll = false
        var frameZoom = 0.0
        for event in events {
            switch event {
            case let .pointerDelta(dx, dy), let .dragDelta(dx, dy):
                pointer = pointer + Point2D(x: dx, y: dy)
                hasPointer = true
            case let .scroll(dx, dy):
                scroll = scroll + Point2D(x: dx, y: dy)
                hasScroll = true
            case let .zoom(delta): frameZoom += delta
            default: break
            }
        }

        let accumulatedZoom = zoomAccumulator.consume(delta: frameZoom, episode: zoomEpisode)
        return InputDiagnosticSnapshot(
            pointerDelta: hasPointer ? pointer : nil,
            scrollDelta: hasScroll ? scroll : nil,
            zoomDistance: zoomDistance,
            accumulatedZoomDelta: accumulatedZoom,
            rawMovement: rawMovement,
            normalizedMovement: normalizedMovement,
            filteredMovement: filteredMovement,
            finalMovement: hasPointer ? pointer.magnitude : nil
        )
    }

    private func movement(from previous: Point2D?, to current: Point2D?) -> Double? {
        guard let previous, let current else { return nil }
        let value = previous.distance(to: current)
        return value.isFinite ? value : nil
    }

}

private extension CameraServiceState {
    var isTerminalForInput: Bool {
        switch self {
        case .stopped, .stopping, .permissionRequired, .interrupted, .unavailable, .failed:
            true
        case .starting, .running:
            false
        }
    }
}

private struct TrackingDelivery: Sendable {
    var snapshot: TrackingSnapshot
    var gesture: GestureFrameResult
}
