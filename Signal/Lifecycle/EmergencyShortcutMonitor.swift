@preconcurrency import AppKit
import CoreGraphics
import Foundation

public struct EmergencyMonitorHealth: Equatable, Sendable {
    public var globalMonitorInstalled: Bool
    public var localMonitorInstalled: Bool

    public init(globalMonitorInstalled: Bool, localMonitorInstalled: Bool) {
        self.globalMonitorInstalled = globalMonitorInstalled
        self.localMonitorInstalled = localMonitorInstalled
    }

    /// A trusted app must have both paths. Without Accessibility trust, normal
    /// output is already prohibited and the local/menu emergency paths remain.
    public func permitsEnable(accessibilityTrusted: Bool) -> Bool {
        localMonitorInstalled && (!accessibilityTrusted || globalMonitorInstalled)
    }
}

public struct EmergencyChordInput: Equatable, Sendable {
    public var charactersIgnoringModifiers: String?
    public var isRepeat: Bool
    public var control: Bool
    public var option: Bool
    public var command: Bool
    public var shift: Bool
    public var eventMarker: Int64?

    public init(
        charactersIgnoringModifiers: String?,
        isRepeat: Bool = false,
        control: Bool,
        option: Bool,
        command: Bool,
        shift: Bool = false,
        eventMarker: Int64? = nil
    ) {
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.isRepeat = isRepeat
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
        self.eventMarker = eventMarker
    }
}

public enum EmergencyShortcutPolicy {
    public static func matches(_ input: EmergencyChordInput, ignoredMarker: Int64?) -> Bool {
        guard !input.isRepeat,
              input.charactersIgnoringModifiers?.lowercased() == "h",
              input.control, input.option, input.command, !input.shift else { return false }
        return ignoredMarker == nil || input.eventMarker != ignoredMarker
    }

    public static func acceptsTrigger(
        uptime: Double,
        previousUptime: Double,
        debounceInterval: TimeInterval
    ) -> Bool {
        uptime.isFinite
            && (previousUptime.isFinite || previousUptime == -.infinity)
            && debounceInterval.isFinite
            && uptime - previousUptime >= max(0, debounceInterval)
    }
}

/// Observes Control-Option-Command-H without intercepting physical input.
///
/// Call `start()` and `stop()` on the main thread. The global, local, and menu
/// paths all converge on one lock-protected debounce and callback.
public final class EmergencyShortcutMonitor: @unchecked Sendable {
    public var onEmergency: (@Sendable () -> Void)? {
        get { withLock { emergencyCallback } }
        set { withLock { emergencyCallback = newValue } }
    }

    public var onHealthChange: (@Sendable (EmergencyMonitorHealth) -> Void)? {
        get { withLock { healthCallback } }
        set { withLock { healthCallback = newValue } }
    }

    public var health: EmergencyMonitorHealth {
        withLock { currentHealthLocked() }
    }

    private let lock = NSLock()
    private let ignoredEventMarker: Int64?
    private let debounceInterval: TimeInterval
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var emergencyCallback: (@Sendable () -> Void)?
    private var healthCallback: (@Sendable (EmergencyMonitorHealth) -> Void)?
    private var lastTriggerUptime = -Double.infinity
    private var monitorGeneration: UInt64 = 0

    public init(
        ignoredEventMarker: Int64? = nil,
        debounceInterval: TimeInterval = 0.250
    ) {
        self.ignoredEventMarker = ignoredEventMarker
        self.debounceInterval = debounceInterval.isFinite
            ? max(0, debounceInterval)
            : 0.250
    }

    deinit {
        let tokens: (Any?, Any?) = withLock {
            monitorGeneration &+= 1
            let tokens = (globalMonitor, localMonitor)
            globalMonitor = nil
            localMonitor = nil
            return tokens
        }
        if let global = tokens.0 { NSEvent.removeMonitor(global) }
        if let local = tokens.1 { NSEvent.removeMonitor(local) }
    }

    @discardableResult
    public func start() -> EmergencyMonitorHealth {
        precondition(Thread.isMainThread, "Emergency monitors must be installed on the main thread")

        let plan: (needsGlobal: Bool, needsLocal: Bool, generation: UInt64) = withLock {
            monitorGeneration &+= 1
            return (globalMonitor == nil, localMonitor == nil, monitorGeneration)
        }

        let newGlobal: Any? = plan.needsGlobal
            ? NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
            }
            : nil
        let newLocal: Any? = plan.needsLocal
            ? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
                return event
            }
            : nil

        var unusedGlobal: Any?
        var unusedLocal: Any?
        let result: EmergencyMonitorHealth = withLock {
            guard monitorGeneration == plan.generation else {
                unusedGlobal = newGlobal
                unusedLocal = newLocal
                return currentHealthLocked()
            }
            if globalMonitor == nil {
                globalMonitor = newGlobal
            } else {
                unusedGlobal = newGlobal
            }
            if localMonitor == nil {
                localMonitor = newLocal
            } else {
                unusedLocal = newLocal
            }
            return currentHealthLocked()
        }

        if let unusedGlobal { NSEvent.removeMonitor(unusedGlobal) }
        if let unusedLocal { NSEvent.removeMonitor(unusedLocal) }
        notifyHealth(result)
        return result
    }

    public func stop() {
        precondition(Thread.isMainThread, "Emergency monitors must be removed on the main thread")

        let tokens: (Any?, Any?) = withLock {
            monitorGeneration &+= 1
            let tokens = (globalMonitor, localMonitor)
            globalMonitor = nil
            localMonitor = nil
            lastTriggerUptime = -Double.infinity
            return tokens
        }
        if let global = tokens.0 { NSEvent.removeMonitor(global) }
        if let local = tokens.1 { NSEvent.removeMonitor(local) }
        notifyHealth(health)
    }

    /// Supplemental key-equivalent path for events consumed during menu
    /// tracking. It uses the same debounce as the AppKit monitor paths.
    public func triggerFromMenu() {
        triggerIfNotDebounced(at: ProcessInfo.processInfo.systemUptime)
    }

    private func handle(_ event: NSEvent) {
        guard EmergencyShortcutPolicy.matches(
            Self.chordInput(from: event),
            ignoredMarker: ignoredEventMarker
        ) else {
            return
        }
        triggerIfNotDebounced(at: ProcessInfo.processInfo.systemUptime)
    }

    private func triggerIfNotDebounced(at uptime: Double) {
        let callback: (@Sendable () -> Void)? = withLock {
            guard emergencyCallback != nil,
                  EmergencyShortcutPolicy.acceptsTrigger(
                    uptime: uptime,
                    previousUptime: lastTriggerUptime,
                    debounceInterval: debounceInterval
                  ) else {
                return nil
            }
            lastTriggerUptime = uptime
            return emergencyCallback
        }
        callback?()
    }

    static func matchesEmergencyChord(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && EmergencyShortcutPolicy.matches(chordInput(from: event), ignoredMarker: nil)
    }

    private static func chordInput(from event: NSEvent) -> EmergencyChordInput {
        let marker = event.cgEvent?.getIntegerValueField(.eventSourceUserData)
        return EmergencyChordInput(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isRepeat: event.isARepeat,
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            eventMarker: marker
        )
    }

    private func notifyHealth(_ health: EmergencyMonitorHealth) {
        let callback = withLock { healthCallback }
        callback?(health)
    }

    private func currentHealthLocked() -> EmergencyMonitorHealth {
        EmergencyMonitorHealth(
            globalMonitorInstalled: globalMonitor != nil,
            localMonitorInstalled: localMonitor != nil
        )
    }

    @discardableResult
    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
