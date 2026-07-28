import Combine
import Foundation

public struct SignalUIActions {
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
    @Published public private(set) var controlIntent: ControlIntent
    @Published public private(set) var status: AppStatus
    @Published public private(set) var cameraAuthorized: Bool
    @Published public private(set) var cameraPermission: CameraPermissionState
    @Published public private(set) var accessibilityTrusted: Bool
    @Published public private(set) var calibrationIsOpen: Bool

    public init(
        controlIntent: ControlIntent = .disabled,
        status: AppStatus = .disabled,
        cameraAuthorized: Bool = false,
        cameraPermission: CameraPermissionState = .unknown,
        accessibilityTrusted: Bool = false,
        calibrationIsOpen: Bool = false
    ) {
        self.controlIntent = controlIntent
        self.status = status
        self.cameraAuthorized = cameraAuthorized
        self.cameraPermission = cameraPermission
        self.accessibilityTrusted = accessibilityTrusted
        self.calibrationIsOpen = calibrationIsOpen
    }

    public func apply(
        controlIntent: ControlIntent,
        status: AppStatus,
        cameraAuthorized: Bool,
        cameraPermission: CameraPermissionState = .unknown,
        accessibilityTrusted: Bool,
        calibrationIsOpen: Bool
    ) {
        self.controlIntent = controlIntent
        self.status = status
        self.cameraAuthorized = cameraAuthorized
        self.cameraPermission = cameraPermission
        self.accessibilityTrusted = accessibilityTrusted
        self.calibrationIsOpen = calibrationIsOpen
    }

    public var statusText: String {
        switch status {
        case .disabled: "Control disabled"
        case .enabled: "Control enabled"
        case .paused: "Control paused"
        case .cameraPermissionMissing: "Camera permission required"
        case .accessibilityPermissionMissing: "Accessibility permission required"
        case .cameraUnavailable: "Camera unavailable"
        case .waitingForHand: "Control enabled — waiting for a clear hand"
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
