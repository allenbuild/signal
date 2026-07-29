import ApplicationServices
import AppKit
import Combine
import Foundation

public enum OptionalPermissionState: String, Equatable, Sendable {
    case granted
    case notDetermined
    case denied
    case unavailable
}

public struct OptionalPermissionSnapshot: Equatable, Sendable {
    public var browserAutomation: OptionalPermissionState
    public var screenRecording: OptionalPermissionState

    public init(
        browserAutomation: OptionalPermissionState,
        screenRecording: OptionalPermissionState
    ) {
        self.browserAutomation = browserAutomation
        self.screenRecording = screenRecording
    }
}

/// Passive checks are safe during construction; permission prompts happen only
/// from the explicit request methods invoked by visible buttons.
@MainActor
public final class OptionalPermissionService: ObservableObject {
    public static let chromeBundleIdentifier = "com.google.Chrome"

    @Published public private(set) var snapshot: OptionalPermissionSnapshot

    private let defaults: UserDefaults
    private let automationAttemptKey = "Signal.permissions.chromeAutomationPrompted"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Construction is intentionally free of TCC and workspace queries.
        // The owning runtime performs a passive refresh only after launch.
        snapshot = OptionalPermissionSnapshot(
            browserAutomation: .notDetermined,
            screenRecording: .notDetermined
        )
    }

    @discardableResult
    public func refresh() -> OptionalPermissionSnapshot {
        snapshot = Self.readSnapshot(defaults: defaults)
        return snapshot
    }

    @discardableResult
    public func requestChromeAutomation() -> OptionalPermissionState {
        defaults.set(true, forKey: automationAttemptKey)
        let state = Self.chromeAutomationState(askUserIfNeeded: true)
        snapshot.browserAutomation = state
        return state
    }

    private static func readSnapshot(
        defaults: UserDefaults
    ) -> OptionalPermissionSnapshot {
        let browserState: OptionalPermissionState
        if !defaults.bool(forKey: "Signal.permissions.chromeAutomationPrompted") {
            browserState = .notDetermined
        } else {
            browserState = chromeAutomationState(askUserIfNeeded: false)
        }

        return OptionalPermissionSnapshot(
            browserAutomation: browserState,
            // The production Teach by Demo recorder retains reviewed
            // structured events and no screen pixels.
            screenRecording: .unavailable
        )
    }

    private static func chromeAutomationState(
        askUserIfNeeded: Bool
    ) -> OptionalPermissionState {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: chromeBundleIdentifier
        ) != nil else {
            return .unavailable
        }

        var target = AEAddressDesc()
        let bytes = Array(chromeBundleIdentifier.utf8)
        let createStatus = bytes.withUnsafeBytes { rawBuffer in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                rawBuffer.baseAddress,
                rawBuffer.count,
                &target
            )
        }
        guard createStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .unavailable
        default:
            return .denied
        }
    }
}
