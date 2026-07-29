import Foundation

public enum GestureResetReason: String, Codable, Equatable, Sendable {
    case disabled, paused, trackingLost, cameraStopped, permissionLost
    case sessionInactive, displayConfigurationChanged, emergency, settingsChanged, shutdown
}

public enum TrackingResetReason: String, Codable, Equatable, Sendable {
    case cameraStopped, interruption, permissionLost, generationChanged
    case extendedGap, shutdown
}

public enum ControlIntent: String, Codable, Equatable, Sendable {
    case disabled, enabled, paused
}

/// The only user-facing runtime modes. `ControlIntent` remains an internal
/// safety gate so existing input fencing can distinguish pending, enabled,
/// and quiesced output without leaking a fourth mode into the product.
public enum SignalMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case paused
    case control
    case commands

    public var title: String {
        switch self {
        case .paused: "Paused"
        case .control: "Control"
        case .commands: "Commands"
        }
    }
}

public enum AppStatus: Equatable, Sendable {
    case disabled, enabled, paused
    case cameraPermissionMissing
    case accessibilityPermissionMissing
    case cameraUnavailable
    case waitingForHand
    case trackingDegraded
    case emergencyStopped
    case error(String)
}

public enum SafetyStopReason: String, Equatable, Sendable {
    case userDisabled, paused, emergency, trackingLost, cameraStopped
    case cameraInterrupted, cameraFailed, cameraPermissionLost
    case accessibilityPermissionLost, sleep, sessionInactive
    case displayConfigurationChanged, shutdown
}

public protocol CameraControlling: AnyObject {
    func start()
    func stop()
}

public protocol GestureResetting: AnyObject {
    @discardableResult
    func reset(reason: GestureResetReason) -> [GestureEvent]
}

public protocol PermissionChecking: AnyObject {
    var cameraAuthorized: Bool { get }
    var accessibilityTrusted: Bool { get }
    func requestCameraAccess(_ completion: @escaping @Sendable (Bool) -> Void)
    func promptForAccessibility()
}

public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    func openLoginItemsSettings()
}

public extension LaunchAtLoginControlling {
    var requiresApproval: Bool { false }
}

public protocol GestureEventProvider: AnyObject {
    var onEvents: (@Sendable ([GestureEvent]) -> Void)? { get set }
    func start()
    func stop()
    @discardableResult
    func reset(reason: GestureResetReason) -> [GestureEvent]
}
