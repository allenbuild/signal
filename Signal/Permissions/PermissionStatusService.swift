@preconcurrency import AVFoundation
@preconcurrency import ApplicationServices
import Foundation

public enum CameraPermissionState: String, Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

public struct PermissionSnapshot: Equatable, Sendable {
    public var camera: CameraPermissionState
    public var accessibilityTrusted: Bool

    public var cameraAuthorized: Bool {
        camera == .authorized
    }

    public init(camera: CameraPermissionState, accessibilityTrusted: Bool) {
        self.camera = camera
        self.accessibilityTrusted = accessibilityTrusted
    }
}

public struct PermissionUpdate: Equatable, Sendable {
    public var revision: UInt64
    public var snapshot: PermissionSnapshot

    public init(revision: UInt64, snapshot: PermissionSnapshot) {
        self.revision = revision
        self.snapshot = snapshot
    }
}

public protocol PermissionSystemProviding: Sendable {
    var cameraState: CameraPermissionState { get }
    var accessibilityTrusted: Bool { get }
    func requestCameraAccess(_ completion: @escaping @Sendable (Bool) -> Void)
    func promptForAccessibility()
}

public struct SystemPermissionProvider: PermissionSystemProviding, Sendable {
    public init() {}

    public var cameraState: CameraPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    public var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    public func requestCameraAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }

    public func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// Passive permission status plus explicit, user-action-only prompt methods.
///
/// This service never prompts during initialization or `refresh()`. App code
/// must call the request methods only from onboarding or a clear user action.
public final class PermissionStatusService: PermissionChecking, @unchecked Sendable {
    public var onChange: (@Sendable (PermissionUpdate) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return changeCallback
        }
        set {
            lock.lock()
            changeCallback = newValue
            lock.unlock()
        }
    }

    public var cameraAuthorized: Bool {
        system.cameraState == .authorized
    }

    public var accessibilityTrusted: Bool {
        system.accessibilityTrusted
    }

    private let lock = NSLock()
    // Keep sampling, revision assignment, and callback delivery ordered while
    // allowing an observer to synchronously inspect the current snapshot.
    private let refreshLock = NSRecursiveLock()
    private var changeCallback: (@Sendable (PermissionUpdate) -> Void)?
    private var lastSnapshot: PermissionSnapshot?
    private var revision: UInt64 = 0
    private let system: PermissionSystemProviding

    public init(system: PermissionSystemProviding = SystemPermissionProvider()) {
        self.system = system
    }

    @discardableResult
    public func refresh() -> PermissionUpdate {
        // Sampling and revision assignment are one serialized operation. A
        // camera-completion refresh can otherwise race an activation refresh
        // and deliver an older snapshot after a newer authorization result.
        refreshLock.lock()
        defer { refreshLock.unlock() }
        let snapshot = sampleSnapshot()

        lock.lock()
        let changed = snapshot != lastSnapshot
        if changed {
            lastSnapshot = snapshot
            revision &+= 1
        }
        let update = PermissionUpdate(revision: revision, snapshot: snapshot)
        let callback = changeCallback
        lock.unlock()

        if changed {
            callback?(update)
        }
        return update
    }

    public func currentSnapshot() -> PermissionSnapshot {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        return sampleSnapshot()
    }

    private func sampleSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            camera: system.cameraState,
            accessibilityTrusted: system.accessibilityTrusted
        )
    }

    /// Must be called only from onboarding or an explicit Grant Camera action.
    public func requestCameraAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard system.cameraState == .notDetermined else {
            let granted = cameraAuthorized
            _ = refresh()
            completion(granted)
            return
        }

        system.requestCameraAccess { [weak self] granted in
            _ = self?.refresh()
            completion(granted)
        }
    }

    /// Must be called only from an explicit Grant Accessibility action.
    public func promptForAccessibility() {
        system.promptForAccessibility()
        _ = refresh()
    }
}
