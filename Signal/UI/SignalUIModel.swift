import Combine
import Foundation

public struct SignalUIActions {
    public var setMode: @MainActor (SignalMode) -> Void
    public var openMainWindow: @MainActor () -> Void
    public var enableControl: @MainActor () -> Void
    public var disableControl: @MainActor () -> Void
    public var pauseControl: @MainActor () -> Void
    public var resumeControl: @MainActor () -> Void
    public var openCalibration: @MainActor () -> Void
    public var closeCalibration: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var requestCameraPermission: @MainActor () -> Void
    public var requestAccessibilityPermission: @MainActor () -> Void
    public var retryCamera: @MainActor () -> Void
    public var emergencyStop: @MainActor () -> Void
    public var quit: @MainActor () -> Void

    public init(
        setMode: @escaping @MainActor (SignalMode) -> Void = { _ in },
        openMainWindow: @escaping @MainActor () -> Void = {},
        enableControl: @escaping @MainActor () -> Void,
        disableControl: @escaping @MainActor () -> Void,
        pauseControl: @escaping @MainActor () -> Void,
        resumeControl: @escaping @MainActor () -> Void,
        openCalibration: @escaping @MainActor () -> Void,
        closeCalibration: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void,
        requestCameraPermission: @escaping @MainActor () -> Void,
        requestAccessibilityPermission: @escaping @MainActor () -> Void,
        retryCamera: @escaping @MainActor () -> Void,
        emergencyStop: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.setMode = setMode
        self.openMainWindow = openMainWindow
        self.enableControl = enableControl
        self.disableControl = disableControl
        self.pauseControl = pauseControl
        self.resumeControl = resumeControl
        self.openCalibration = openCalibration
        self.closeCalibration = closeCalibration
        self.openSettings = openSettings
        self.requestCameraPermission = requestCameraPermission
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.retryCamera = retryCamera
        self.emergencyStop = emergencyStop
        self.quit = quit
    }
}

@MainActor
public final class SignalUIModel: ObservableObject {
    @Published public private(set) var dashboardPresentation:
        SignalDashboardPresentation
    @Published public private(set) var mode: SignalMode
    @Published public private(set) var controlIntent: ControlIntent
    @Published public private(set) var status: AppStatus
    @Published public private(set) var cameraAuthorized: Bool
    @Published public private(set) var cameraPermission: CameraPermissionState
    @Published public private(set) var accessibilityTrusted: Bool
    @Published public private(set) var calibrationIsOpen: Bool
    private var optionalPermissions: OptionalPermissionSnapshot

    public init(
        mode: SignalMode = .paused,
        controlIntent: ControlIntent = .disabled,
        status: AppStatus = .disabled,
        cameraAuthorized: Bool = false,
        cameraPermission: CameraPermissionState = .unknown,
        accessibilityTrusted: Bool = false,
        calibrationIsOpen: Bool = false,
        optionalPermissions: OptionalPermissionSnapshot = .init(
            browserAutomation: .notDetermined,
            screenRecording: .notDetermined
        )
    ) {
        dashboardPresentation = SignalDashboardPresentation()
        self.mode = mode
        self.controlIntent = controlIntent
        self.status = status
        self.cameraAuthorized = cameraAuthorized
        self.cameraPermission = cameraPermission
        self.accessibilityTrusted = accessibilityTrusted
        self.calibrationIsOpen = calibrationIsOpen
        self.optionalPermissions = optionalPermissions
    }

    public func apply(
        controlIntent: ControlIntent,
        status: AppStatus,
        cameraAuthorized: Bool,
        cameraPermission: CameraPermissionState = .unknown,
        accessibilityTrusted: Bool,
        calibrationIsOpen: Bool,
        mode: SignalMode? = nil
    ) {
        if let mode {
            self.mode = mode
        }
        self.controlIntent = controlIntent
        self.status = status
        self.cameraAuthorized = cameraAuthorized
        self.cameraPermission = cameraPermission
        self.accessibilityTrusted = accessibilityTrusted
        self.calibrationIsOpen = calibrationIsOpen
        updateDashboardShell()
    }

    public func updateTracking(
        snapshot: TrackingSnapshot,
        gesture: GestureFrameResult,
        cameraState: String
    ) {
        dashboardPresentation.telemetry.cameraState = cameraState
        dashboardPresentation.telemetry.trackingQuality =
            snapshot.quality.rawValue.capitalized
        dashboardPresentation.telemetry.recognizedPose =
            gesture.diagnostics.recognizedPose?.rawValue ?? "None"
        dashboardPresentation.telemetry.confidence =
            gesture.diagnostics.requiredJointConfidence ?? 0
        dashboardPresentation.telemetry.captureFPS =
            snapshot.diagnostics.captureFPS
        dashboardPresentation.telemetry.processedFPS =
            snapshot.diagnostics.processedFPS
        dashboardPresentation.telemetry.visionLatencyMilliseconds =
            snapshot.diagnostics.visionLatencyMilliseconds
        dashboardPresentation.telemetry.endToEndLatencyMilliseconds =
            snapshot.diagnostics.endToEndLatencyMilliseconds
        dashboardPresentation.telemetry.controlTransaction =
            gesture.diagnostics.activeGesture.rawValue
    }

    public func updateCameraState(_ cameraState: String, resetMetrics: Bool) {
        dashboardPresentation.telemetry.cameraState = cameraState
        guard resetMetrics else { return }
        dashboardPresentation.telemetry.captureFPS = 0
        dashboardPresentation.telemetry.processedFPS = 0
        dashboardPresentation.telemetry.visionLatencyMilliseconds = 0
        dashboardPresentation.telemetry.endToEndLatencyMilliseconds = 0
    }

    public func updateCameraDiagnostics(_ diagnostics: CameraDiagnosticsSnapshot) {
        dashboardPresentation.telemetry.captureFPS = diagnostics.captureFPS
        dashboardPresentation.telemetry.processedFPS = diagnostics.processedFPS
        dashboardPresentation.telemetry.visionLatencyMilliseconds =
            diagnostics.latestProcessingLatencyMilliseconds
        dashboardPresentation.telemetry.endToEndLatencyMilliseconds =
            diagnostics.latestEndToEndLatencyMilliseconds ?? 0
    }

    public func updateCommandActivation(
        cardID: SignalDashboardCardID?,
        progress: Double
    ) {
        dashboardPresentation.setActivation(cardID: cardID, progress: progress)
    }

    public func updateCommandDocument(_ document: SignalCommandDocument) {
        guard let fist = document.profile[.fist] else { return }
        dashboardPresentation.updateFistCommand(
            name: fist.name,
            isConfigured: fist.plan != nil
        )
    }

    public func recordActivity(_ entry: SignalDashboardActivity) {
        dashboardPresentation.recordActivity(entry)
    }

    public func reportCommand(name: String, result: String, succeeded: Bool) {
        dashboardPresentation.lastCommand = name
        dashboardPresentation.lastCommandResult = result
        dashboardPresentation.recordActivity(
            SignalDashboardActivity(
                title: name,
                detail: result,
                outcome: succeeded ? .success : .failure
            )
        )
    }

    public func updateOptionalPermissions(_ snapshot: OptionalPermissionSnapshot) {
        optionalPermissions = snapshot
        updateDashboardShell()
    }

    private func updateDashboardShell() {
        dashboardPresentation.mode = switch mode {
        case .paused: .paused
        case .control: .control
        case .commands: .commands
        }
        dashboardPresentation.status = SignalDashboardStatus(
            kind: dashboardStatusKind,
            title: statusText,
            detail: dashboardStatusDetail
        )
        dashboardPresentation.permissions = [
            SignalDashboardPermission(
                kind: .camera,
                state: dashboardCameraPermission
            ),
            SignalDashboardPermission(
                kind: .accessibility,
                state: accessibilityTrusted ? .granted : .notDetermined,
                detail: "Required for system cursor, click, scroll, and zoom."
            ),
            SignalDashboardPermission(
                kind: .browserAutomation,
                state: dashboardOptionalPermission(
                    optionalPermissions.browserAutomation
                ),
                detail: "Used only by Bolt and Spotify Web commands."
            ),
            SignalDashboardPermission(
                kind: .screenRecording,
                state: .notRequired,
                detail: "The current structured Teach by Demo recorder does not capture screen pixels."
            ),
        ]
        if mode != .commands {
            dashboardPresentation.setActivation(cardID: nil, progress: 0)
        }
    }

    private var dashboardStatusKind: SignalDashboardStatusKind {
        switch status {
        case .enabled: .ready
        case .waitingForHand: .attention
        case .disabled, .paused: .paused
        case .cameraPermissionMissing, .accessibilityPermissionMissing,
             .cameraUnavailable, .trackingDegraded, .emergencyStopped:
            .attention
        case .error:
            .error
        }
    }

    private var dashboardStatusDetail: String {
        switch mode {
        case .paused:
            "No cursor, scroll, zoom, or command output is active."
        case .control:
            "Control Mode moves the system pointer. Programmable commands are disabled."
        case .commands:
            "Command Mode runs the eight reviewed gestures. Native pointer output is disabled."
        }
    }

    private var dashboardCameraPermission: SignalDashboardPermissionState {
        switch cameraPermission {
        case .authorized: .granted
        case .notDetermined, .unknown: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        }
    }

    private func dashboardOptionalPermission(
        _ state: OptionalPermissionState
    ) -> SignalDashboardPermissionState {
        switch state {
        case .granted: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .unavailable: .notRequired
        }
    }

    public var statusText: String {
        switch status {
        case .disabled: "Control disabled"
        case .enabled: "Control enabled"
        case .paused: "Control paused"
        case .cameraPermissionMissing: "Camera permission required"
        case .accessibilityPermissionMissing: "Accessibility permission required"
        case .cameraUnavailable: "Camera unavailable"
        case .waitingForHand:
            mode == .commands
                ? "Commands ready — waiting for a clear hand"
                : "Control enabled — waiting for a clear hand"
        case .trackingDegraded: "Camera feed stalled — control stopped"
        case .emergencyStopped: "Emergency stop active"
        case let .error(message): "Error: \(message)"
        }
    }

    public var statusSymbol: String {
        switch status {
        case .enabled: "hand.point.up.left.fill"
        case .waitingForHand: "hand.raised.fill"
        case .paused: "pause.circle"
        case .trackingDegraded: "hand.raised"
        case .cameraPermissionMissing, .accessibilityPermissionMissing,
             .cameraUnavailable, .emergencyStopped, .error:
            "exclamationmark.shield"
        case .disabled:
            "hand.raised.slash"
        }
    }

    public var statusIsWarning: Bool {
        switch status {
        case .cameraPermissionMissing, .accessibilityPermissionMissing,
             .cameraUnavailable, .trackingDegraded, .emergencyStopped, .error:
            true
        case .disabled, .enabled, .paused, .waitingForHand:
            false
        }
    }
}
