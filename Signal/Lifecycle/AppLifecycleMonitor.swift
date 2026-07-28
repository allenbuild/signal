@preconcurrency import AppKit
import Foundation

public enum AppLifecycleSignal: String, Equatable, Sendable {
    case willSleep
    case didWake
    case screensDidSleep
    case screensDidWake
    case sessionDidResignActive
    case sessionDidBecomeActive
    case willPowerOff
    case applicationWillTerminate
    case applicationDidBecomeActive
    case displayConfigurationChanged

    public var safetyStopReason: SafetyStopReason? {
        switch self {
        case .willSleep, .screensDidSleep: .sleep
        case .sessionDidResignActive: .sessionInactive
        case .willPowerOff, .applicationWillTerminate: .shutdown
        case .displayConfigurationChanged: .displayConfigurationChanged
        case .didWake, .screensDidWake, .sessionDidBecomeActive,
             .applicationDidBecomeActive:
            nil
        }
    }

    public var requestsStatusRefresh: Bool {
        switch self {
        case .didWake, .screensDidWake, .sessionDidBecomeActive,
             .applicationDidBecomeActive:
            true
        case .willSleep, .screensDidSleep, .sessionDidResignActive,
             .willPowerOff, .applicationWillTerminate,
             .displayConfigurationChanged:
            false
        }
    }
}

/// Converts AppKit/workspace notifications into coordinator-facing signals.
/// It does not own Camera, Input, AppState, or any system event posting.
public final class AppLifecycleMonitor: @unchecked Sendable {
    public var onSignal: (@Sendable (AppLifecycleSignal) -> Void)? {
        get { withLock { signalCallback } }
        set { withLock { signalCallback = newValue } }
    }

    public var onSafetyStop: (@Sendable (SafetyStopReason) -> Void)? {
        get { withLock { safetyStopCallback } }
        set { withLock { safetyStopCallback = newValue } }
    }

    public var onStatusRefreshRequested: (@Sendable () -> Void)? {
        get { withLock { refreshCallback } }
        set { withLock { refreshCallback = newValue } }
    }

    public var isRunning: Bool {
        withLock { running }
    }

    private struct Observation {
        var center: NotificationCenter
        var token: NSObjectProtocol
    }

    private let lock = NSLock()
    private var observations: [Observation] = []
    private var running = false
    private var monitorGeneration: UInt64 = 0
    private var signalCallback: (@Sendable (AppLifecycleSignal) -> Void)?
    private var safetyStopCallback: (@Sendable (SafetyStopReason) -> Void)?
    private var refreshCallback: (@Sendable () -> Void)?

    public init() {
        observations.reserveCapacity(10)
    }

    deinit {
        stop()
    }

    public func start() {
        let generation: UInt64? = withLock {
            guard !running else { return nil }
            running = true
            monitorGeneration &+= 1
            return monitorGeneration
        }
        guard let generation else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        let registrations: [(NotificationCenter, Notification.Name, AppLifecycleSignal)] = [
            (workspaceCenter, NSWorkspace.willSleepNotification, .willSleep),
            (workspaceCenter, NSWorkspace.didWakeNotification, .didWake),
            (workspaceCenter, NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (workspaceCenter, NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (workspaceCenter, NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive),
            (workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
            (workspaceCenter, NSWorkspace.willPowerOffNotification, .willPowerOff),
            (appCenter, NSApplication.willTerminateNotification, .applicationWillTerminate),
            (appCenter, NSApplication.didBecomeActiveNotification, .applicationDidBecomeActive),
            (appCenter, NSApplication.didChangeScreenParametersNotification, .displayConfigurationChanged)
        ]

        let newObservations = registrations.map { center, name, signal in
            let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.process(signal)
            }
            return Observation(center: center, token: token)
        }

        let keepObservations = withLock {
            guard running, monitorGeneration == generation else { return false }
            observations.append(contentsOf: newObservations)
            return true
        }
        if !keepObservations {
            newObservations.forEach { $0.center.removeObserver($0.token) }
        }
    }

    public func stop() {
        let oldObservations: [Observation] = withLock {
            running = false
            monitorGeneration &+= 1
            let old = observations
            observations.removeAll(keepingCapacity: true)
            return old
        }
        oldObservations.forEach { $0.center.removeObserver($0.token) }
    }

    /// Pure ordering boundary shared by NotificationCenter delivery and
    /// deterministic tests: safety stop, signal, then recovery refresh.
    func process(_ signal: AppLifecycleSignal) {
        let callbacks = withLock {
            (signalCallback, safetyStopCallback, refreshCallback)
        }

        if let reason = signal.safetyStopReason {
            callbacks.1?(reason)
        }
        callbacks.0?(signal)
        if signal.requestsStatusRefresh {
            callbacks.2?()
        }
    }

    @discardableResult
    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
