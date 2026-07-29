import Foundation

/// The command and dashboard identities for one recognized command pose.
///
/// `CommandGesture` remains the geometry-facing identity, while
/// `SignalCommandGesture` and `SignalDashboardCardID` are the stable semantic
/// identities consumed by the command domain and dashboard.
public struct SignalCommandRecognitionMatch: Equatable, Sendable {
    public var sourceGesture: CommandGesture
    public var commandGesture: SignalCommandGesture
    public var cardID: SignalDashboardCardID
    public var confidence: Double
    public var requiredJointConfidence: Double

    public init(
        sourceGesture: CommandGesture,
        commandGesture: SignalCommandGesture,
        cardID: SignalDashboardCardID,
        confidence: Double,
        requiredJointConfidence: Double
    ) {
        self.sourceGesture = sourceGesture
        self.commandGesture = commandGesture
        self.cardID = cardID
        self.confidence = confidence
        self.requiredJointConfidence = requiredJointConfidence
    }
}

/// Why command recognition discarded all in-flight activation state.
public enum SignalCommandRecognitionResetReason: Equatable, Sendable {
    case explicit
    case modeChanged(from: SignalMode, to: SignalMode)
    case inactiveMode(SignalMode)
    case trackingUnavailable(TrackingDegradationReason?)
    case handSelection(count: Int)
    case unreliableHand(HandTrackID)
    case invalidTimestamp
    case timestampRegression
    case captureGenerationChanged(from: UInt64, to: UInt64)
}

/// A value-only result from one serialized command-recognition transition.
///
/// The runtime never executes a command or emits Control input. A coordinator
/// may use `cardID` for presentation and treat only `triggered` as a request to
/// perform a separately authorized command lookup.
public enum SignalCommandRecognitionEvent: Equatable, Sendable {
    case reset(SignalCommandRecognitionResetReason)
    case idle(timestamp: MonotonicTimestamp)
    case progressing(
        timestamp: MonotonicTimestamp,
        match: SignalCommandRecognitionMatch,
        progress: Double
    )
    case triggered(
        timestamp: MonotonicTimestamp,
        match: SignalCommandRecognitionMatch
    )
    case waitingForRelease(
        timestamp: MonotonicTimestamp,
        match: SignalCommandRecognitionMatch
    )
}

/// Pure command-domain adapter from tracking snapshots to activation events.
///
/// All mutable state is protected by `lock`, so a coordinator may safely
/// deliver mode and tracking transitions from different serial executors.
/// Calls still have a deterministic total order: whichever call acquires the
/// lock first is applied first.
public final class SignalCommandRecognitionRuntime: @unchecked Sendable {
    private struct State {
        var mode: SignalMode
        var activationEngine: SignalCommandActivationEngine
        var lastCaptureGeneration: UInt64?
        var lastTimestamp: MonotonicTimestamp?
    }

    private let classifier: CommandGestureClassifier
    private let minimumReliableHandConfidence: Double
    private let lock = NSLock()
    private var state: State

    public init(
        mode: SignalMode = .paused,
        classifier: CommandGestureClassifier = .init(),
        activationConfiguration: SignalCommandActivationConfiguration = .init(),
        minimumReliableHandConfidence: Double =
            GestureTuning.safeDefaults.minimumLandmarkConfidence
    ) {
        self.classifier = classifier
        self.minimumReliableHandConfidence = Self.unitInterval(
            minimumReliableHandConfidence
        )
        self.state = State(
            mode: mode,
            activationEngine: SignalCommandActivationEngine(
                configuration: activationConfiguration
            ),
            lastCaptureGeneration: nil,
            lastTimestamp: nil
        )
    }

    public var mode: SignalMode {
        withLock { $0.mode }
    }

    /// Changes runtime mode and atomically clears every activation latch.
    ///
    /// Reapplying the current mode is a no-op and returns `nil`.
    @discardableResult
    public func setMode(
        _ newMode: SignalMode
    ) -> SignalCommandRecognitionEvent? {
        withLock { state in
            let oldMode = state.mode
            guard oldMode != newMode else { return nil }
            state.mode = newMode
            Self.resetRecognitionState(&state, clearCaptureGeneration: true)
            return .reset(.modeChanged(from: oldMode, to: newMode))
        }
    }

    /// Explicitly clears activation, release latch, timestamp, and capture
    /// generation state.
    @discardableResult
    public func reset() -> SignalCommandRecognitionEvent {
        withLock { state in
            Self.resetRecognitionState(&state, clearCaptureGeneration: true)
            return .reset(.explicit)
        }
    }

    /// Consumes one tracking snapshot without performing any external effect.
    ///
    /// Only `.commands` mode and exactly one current, reliable hand are
    /// eligible. The activation engine receives `snapshot.timestamp.rawValue`
    /// directly; wall-clock and process-uptime clocks are never consulted.
    public func process(
        _ snapshot: TrackingSnapshot
    ) -> SignalCommandRecognitionEvent {
        withLock { state in
            guard state.mode == .commands else {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: true
                )
                return .reset(.inactiveMode(state.mode))
            }

            let seconds = snapshot.timestamp.rawValue
            guard seconds.isFinite else {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                return .reset(.invalidTimestamp)
            }

            if let generation = state.lastCaptureGeneration,
               generation != snapshot.captureGeneration {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                state.lastCaptureGeneration = snapshot.captureGeneration
                return .reset(
                    .captureGenerationChanged(
                        from: generation,
                        to: snapshot.captureGeneration
                    )
                )
            }
            state.lastCaptureGeneration = snapshot.captureGeneration

            if let lastTimestamp = state.lastTimestamp,
               snapshot.timestamp < lastTimestamp {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                return .reset(.timestampRegression)
            }

            guard snapshot.quality == .good,
                  snapshot.degradationReason == nil else {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                return .reset(
                    .trackingUnavailable(snapshot.degradationReason)
                )
            }

            let currentHands = snapshot.hands.filter {
                $0.missingDuration.isFinite && $0.missingDuration <= 0
            }
            guard currentHands.count == 1 else {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                let reason: SignalCommandRecognitionResetReason =
                    currentHands.isEmpty
                    ? .trackingUnavailable(.noHandDetected)
                    : .handSelection(count: currentHands.count)
                return .reset(reason)
            }

            let hand = currentHands[0]
            guard isReliable(hand) else {
                Self.resetRecognitionState(
                    &state,
                    clearCaptureGeneration: false
                )
                return .reset(.unreliableHand(hand.id))
            }

            state.lastTimestamp = snapshot.timestamp
            guard let candidate = classifier.classify(hand) else {
                _ = state.activationEngine.process(
                    SignalCommandActivationSample(
                        monotonicSeconds: seconds,
                        gesture: nil,
                        confidence: 0
                    )
                )
                return .idle(timestamp: snapshot.timestamp)
            }

            let match = Self.match(
                for: candidate.gesture,
                confidence: candidate.confidence,
                requiredJointConfidence: candidate.requiredJointConfidence
            )
            let activation = state.activationEngine.process(
                SignalCommandActivationSample(
                    monotonicSeconds: seconds,
                    gesture: match.commandGesture,
                    confidence: match.confidence
                )
            )
            return Self.event(
                activation,
                timestamp: snapshot.timestamp,
                match: match
            )
        }
    }

    /// Exhaustive, one-to-one mapping for Signal's eight command gestures.
    public static func identity(
        for gesture: CommandGesture
    ) -> (
        commandGesture: SignalCommandGesture,
        cardID: SignalDashboardCardID
    ) {
        switch gesture {
        case .one:
            (.one, .one)
        case .two:
            (.two, .two)
        case .three:
            (.three, .three)
        case .four:
            (.four, .four)
        case .thumbsUp:
            (.thumbsUp, .thumbsUp)
        case .thumbsDown:
            (.thumbsDown, .thumbsDown)
        case .cShape:
            (.cShape, .cShape)
        case .fist:
            (.fist, .fist)
        }
    }

    private func isReliable(_ hand: TrackedHandSnapshot) -> Bool {
        hand.associationCertain
            && hand.timestamp.rawValue.isFinite
            && hand.missingDuration.isFinite
            && hand.missingDuration <= 0
            && hand.palmScaleSource != .unavailable
            && hand.palmWidth.isFinite
            && hand.palmWidth >= 0.02
            && hand.palmWidth <= 0.80
            && hand.confidence.isFinite
            && hand.confidence >= minimumReliableHandConfidence
    }

    private static func match(
        for gesture: CommandGesture,
        confidence: Double,
        requiredJointConfidence: Double
    ) -> SignalCommandRecognitionMatch {
        let identity = identity(for: gesture)
        return SignalCommandRecognitionMatch(
            sourceGesture: gesture,
            commandGesture: identity.commandGesture,
            cardID: identity.cardID,
            confidence: confidence,
            requiredJointConfidence: requiredJointConfidence
        )
    }

    private static func event(
        _ activation: SignalCommandActivationEvent,
        timestamp: MonotonicTimestamp,
        match: SignalCommandRecognitionMatch
    ) -> SignalCommandRecognitionEvent {
        switch activation {
        case .idle:
            .idle(timestamp: timestamp)
        case .progressing(_, let progress):
            .progressing(
                timestamp: timestamp,
                match: match,
                progress: progress
            )
        case .triggered:
            .triggered(timestamp: timestamp, match: match)
        case .waitingForRelease:
            .waitingForRelease(timestamp: timestamp, match: match)
        }
    }

    private static func resetRecognitionState(
        _ state: inout State,
        clearCaptureGeneration: Bool
    ) {
        state.activationEngine.reset()
        state.lastTimestamp = nil
        if clearCaptureGeneration {
            state.lastCaptureGeneration = nil
        }
    }

    private static func unitInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private func withLock<Result>(
        _ operation: (inout State) -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&state)
    }
}
