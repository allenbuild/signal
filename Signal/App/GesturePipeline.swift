import Foundation

/// Serial ownership boundary between Tracking and the deterministic gesture
/// engine. Tracking calls this synchronously on the camera output lane; the
/// concrete input sink performs its own queueing and gate validation.
final class GesturePipeline: GestureResetting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.allenxu.Signal.gesture")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let engine: GestureEngine
    private weak var inputSink: InputSink?
    private var suppressionMode: TransientSuppressionMode?

    init(tuning: GestureTuning, inputSink: InputSink) {
        engine = GestureEngine(tuning: tuning)
        self.inputSink = inputSink
        queue.setSpecific(key: queueKey, value: 1)
    }

    func process(_ snapshot: TrackingSnapshot) -> GestureFrameResult {
        performSync {
            let result = engine.process(snapshot)
            let nextSuppressionMode = TransientSuppressionMode(result.diagnostics)
            if let nextSuppressionMode, nextSuppressionMode != suppressionMode {
                if nextSuppressionMode == .tracking {
                    (inputSink as? TrackingOutputSuspending)?.suspendForTrackingUnavailable()
                } else {
                    (inputSink as? TransientOutputClutching)?.clutchPendingNormalOutput()
                }
            }
            suppressionMode = nextSuppressionMode
            result.events.forEach { event in
                if let sink = inputSink as? CaptureGenerationInputSink,
                   snapshot.captureGeneration != 0 {
                    sink.handle(event, captureGeneration: snapshot.captureGeneration)
                } else {
                    inputSink?.handle(event)
                }
            }
            return result
        }
    }

    @discardableResult
    func advance(to timestamp: MonotonicTimestamp, forwardNormalOutput: Bool) -> [GestureEvent] {
        performSync {
            let events = engine.advance(to: timestamp)
            if events.contains(.trackingLost) {
                suppressionMode = nil
            }
            for event in events where forwardNormalOutput || event.isCleanupEvent {
                inputSink?.handle(event)
            }
            return events
        }
    }

    func update(tuning: GestureTuning) {
        performSync {
            engine.update(tuning: tuning)
            suppressionMode = nil
        }
    }

    var trackingLossGraceDuration: TimeInterval {
        performSync { engine.currentTuning.trackingLossGraceDuration }
    }

    @discardableResult
    func reset(reason: GestureResetReason) -> [GestureEvent] {
        performSync {
            suppressionMode = nil
            return engine.reset(reason: reason)
        }
    }

    private func performSync<Result>(_ operation: () -> Result) -> Result {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }
}

private enum TransientSuppressionMode: Equatable {
    case pinch
    case scroll
    case zoom
    case tracking

    init?(_ diagnostics: GestureDiagnostics) {
        switch diagnostics.pointerSuppressionReason {
        case .some(.middleThumbPinchCandidate), .some(.pendingClick):
            self = .pinch
        case .some(.scrolling):
            self = .scroll
        case .some(.horizontalPinchZoom):
            self = .zoom
        case .some(.multipleHands), .some(.trackingUnavailable), .some(.poseMismatch):
            self = .tracking
        case .none:
            switch diagnostics.activeGesture {
            case .pendingClick: self = .pinch
            case .scroll: self = .scroll
            case .zoom: self = .zoom
            case .rest, .pointer: return nil
            }
        }
    }
}

/// Real-time absence watchdog. It advances the deterministic gesture clock
/// exactly once after the last accepted frame's loss grace expires. The
/// production timer and deterministic `check(now:)` seam share the same path.
final class TrackingLossWatchdog: @unchecked Sendable {
    typealias FireHandler = @Sendable (MonotonicTimestamp, UInt64) -> Void
    static let firstSnapshotTimeout: TimeInterval = 2.0

    private struct Arm {
        var receiptUptime: Double
        var sourceTimestamp: MonotonicTimestamp
        var captureGeneration: UInt64
        var grace: TimeInterval
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.allenxu.Signal.tracking-watchdog")
    private let now: @Sendable () -> Double
    private var fireHandler: FireHandler?
    private var armState: Arm?
    private lazy var timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            _ = self.check(now: self.now())
        }
        timer.resume()
        return timer
    }()

    init(
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        onFire: FireHandler? = nil
    ) {
        self.now = now
        fireHandler = onFire
    }

    var onFire: FireHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return fireHandler
        }
        set {
            lock.lock()
            fireHandler = newValue
            lock.unlock()
        }
    }

    func arm(snapshot: TrackingSnapshot, grace: TimeInterval) {
        let receipt = now()
        arm(
            receiptUptime: receipt,
            sourceTimestamp: snapshot.timestamp,
            captureGeneration: snapshot.captureGeneration,
            grace: grace
        )
    }

    /// Arms liveness before the first tracking snapshot exists. This closes
    /// the gap where AVFoundation reports running but the capture/processing
    /// pipeline never produces its first accepted result.
    func armWaitingForFirstSnapshot(
        captureGeneration: UInt64,
        timeout: TimeInterval = TrackingLossWatchdog.firstSnapshotTimeout
    ) {
        let receipt = now()
        let safeTimeout = max(
            0,
            min(
                timeout.isFinite ? timeout : 0,
                Self.firstSnapshotTimeout
            )
        )
        lock.lock()
        // A real snapshot may race this main-actor startup arm. Never replace
        // its tighter steady-state deadline for the same running generation.
        guard armState?.captureGeneration != captureGeneration else {
            lock.unlock()
            return
        }
        armState = Arm(
            receiptUptime: receipt,
            sourceTimestamp: MonotonicTimestamp(rawValue: receipt),
            captureGeneration: captureGeneration,
            grace: safeTimeout
        )
        timer.schedule(deadline: .now() + safeTimeout, leeway: .milliseconds(5))
        lock.unlock()
    }

    private func arm(
        receiptUptime: Double,
        sourceTimestamp: MonotonicTimestamp,
        captureGeneration: UInt64,
        grace: TimeInterval
    ) {
        let safeGrace = max(
            0,
            min(
                grace.isFinite ? grace : 0,
                GestureTuning.maximumTrackingLossGraceDuration
            )
        )
        lock.lock()
        armState = Arm(
            receiptUptime: receiptUptime,
            sourceTimestamp: sourceTimestamp,
            captureGeneration: captureGeneration,
            grace: safeGrace
        )
        timer.schedule(deadline: .now() + safeGrace, leeway: .milliseconds(2))
        lock.unlock()
    }

    func disarm() {
        lock.lock()
        armState = nil
        timer.schedule(deadline: .distantFuture)
        lock.unlock()
    }

    @discardableResult
    func check(now current: Double) -> Bool {
        lock.lock()
        guard let fired = armState,
              current.isFinite,
              current - fired.receiptUptime + 1e-9 >= fired.grace else {
            lock.unlock()
            return false
        }
        armState = nil
        let elapsed = max(0, current - fired.receiptUptime)
        // Invoke before releasing the watchdog lock. A concurrently arriving
        // frame must order wholly before or wholly after this terminal fence;
        // it cannot replace the arm in the gap between expiry and cleanup.
        fireHandler?(
            MonotonicTimestamp(rawValue: fired.sourceTimestamp.rawValue + elapsed),
            fired.captureGeneration
        )
        lock.unlock()
        return true
    }
}

/// Bounded main-actor handoff: one scheduled task and one replaceable pending
/// value. `invalidate()` advances an epoch so a pre-stop delivery cannot run.
final class LatestOnlyMainActorDelivery<Value: Sendable>: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (Value) -> Void

    private let lock = NSLock()
    private var epoch: UInt64 = 0
    private var scheduled = false
    private var pending: (epoch: UInt64, value: Value, handler: Handler)?
    private let dequeueHook: (@Sendable () -> Void)?

    init(dequeueHook: (@Sendable () -> Void)? = nil) {
        self.dequeueHook = dequeueHook
    }

    func submit(_ value: Value, handler: @escaping Handler) {
        let shouldSchedule: Bool = {
            lock.lock()
            defer { lock.unlock() }
            pending = (epoch, value, handler)
            guard !scheduled else { return false }
            scheduled = true
            return true
        }()
        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in self?.drain() }
    }

    /// A terminal value may not be replaced by later diagnostics. Invalidate
    /// the coalesced lane and enqueue this handler independently. If a later
    /// ordinary delivery runs before or after it, terminal state still wins:
    /// post-terminal handlers cannot reopen the revoked safety lease.
    func submitUncoalesced(_ value: Value, handler: @escaping Handler) {
        invalidate()
        Task { @MainActor in handler(value) }
    }

    func invalidate() {
        lock.lock()
        epoch &+= 1
        pending = nil
        lock.unlock()
    }

    @MainActor
    private func drain() {
        let delivery: (Value, Handler)? = {
            lock.lock()
            defer { lock.unlock() }
            scheduled = false
            guard let pending, pending.epoch == epoch else {
                self.pending = nil
                return nil
            }
            self.pending = nil
            return (pending.value, pending.handler)
        }()
        guard let (value, handler) = delivery else { return }
        dequeueHook?()
        handler(value)
    }
}

/// Explicit-enable capability shared by the main actor and producer safety
/// callbacks. Revocation and enable begin are ordered by the same lock, so a
/// dequeued stale delivery cannot reopen Input after a safety fence.
final class SafetyEnableLease: @unchecked Sendable {
    struct Token: Equatable, Sendable {
        fileprivate var generation: UInt64
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var valid = false

    func issue() -> Token {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        valid = true
        return Token(generation: generation)
    }

    func revoke() {
        lock.lock()
        generation &+= 1
        valid = false
        lock.unlock()
    }

    func isValid(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid && token.generation == generation
    }

    @discardableResult
    func withValid<Result>(_ token: Token, _ body: () -> Result) -> Result? {
        lock.lock()
        defer { lock.unlock() }
        guard valid, token.generation == generation else { return nil }
        return body()
    }
}

/// One producer-side operation used by Camera, permission, lifecycle,
/// emergency, input-fault, tracking-loss, and watchdog callbacks.
enum ProducerSafetySource: String, CaseIterable, Sendable {
    case watchdog
    case trackingLost
    case cameraTerminal
    case permissionLost
    case inputFault
    case lifecycle
    case emergency
    case emergencyMonitorUnhealthy
}

final class ProducerSafetyFence: @unchecked Sendable {
    private let lease: SafetyEnableLease
    private let invalidateDeliveries: @Sendable () -> Void
    private let releaseInput: @Sendable () -> Void

    init(
        lease: SafetyEnableLease,
        invalidateDeliveries: @escaping @Sendable () -> Void,
        releaseInput: @escaping @Sendable () -> Void
    ) {
        self.lease = lease
        self.invalidateDeliveries = invalidateDeliveries
        self.releaseInput = releaseInput
    }

    func revoke(for _: ProducerSafetySource) {
        lease.revoke()
        invalidateDeliveries()
        releaseInput()
    }
}

private extension GestureEvent {
    var isCleanupEvent: Bool {
        switch self {
        case .dragEnd, .trackingLost: true
        default: false
        }
    }
}
