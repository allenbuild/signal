import Foundation

public struct SignalCommandActivationConfiguration: Codable, Equatable, Sendable {
    public var holdDuration: TimeInterval
    public var cooldownDuration: TimeInterval
    public var confidenceThreshold: Double

    public init(
        holdDuration: TimeInterval = 0.60,
        cooldownDuration: TimeInterval = 0.90,
        confidenceThreshold: Double = 0.62
    ) {
        self.holdDuration = holdDuration.isFinite
            ? max(holdDuration, 0.05)
            : 0.60
        self.cooldownDuration = cooldownDuration.isFinite
            ? max(cooldownDuration, 0)
            : 0.90
        self.confidenceThreshold = confidenceThreshold.isFinite
            ? min(max(confidenceThreshold, 0), 1)
            : 0.62
    }

    fileprivate func validated() -> Self {
        Self(
            holdDuration: holdDuration,
            cooldownDuration: cooldownDuration,
            confidenceThreshold: confidenceThreshold
        )
    }
}

public struct SignalCommandActivationSample: Equatable, Sendable {
    public var monotonicSeconds: TimeInterval
    public var gesture: SignalCommandGesture?
    public var confidence: Double

    public init(
        monotonicSeconds: TimeInterval,
        gesture: SignalCommandGesture?,
        confidence: Double
    ) {
        self.monotonicSeconds = monotonicSeconds
        self.gesture = gesture
        self.confidence = confidence
    }
}

public enum SignalCommandActivationEvent: Equatable, Sendable {
    case idle
    case progressing(gesture: SignalCommandGesture, progress: Double)
    case triggered(SignalCommandGesture)
    case waitingForRelease(SignalCommandGesture)
}

/// Deterministic stable-hold activation with a release latch and global cooldown.
public struct SignalCommandActivationEngine: Sendable {
    public var configuration: SignalCommandActivationConfiguration

    private var candidate: SignalCommandGesture?
    private var candidateSince: TimeInterval?
    private var latchedGesture: SignalCommandGesture?
    private var lastTriggerAt: TimeInterval?
    private var lastTimestamp: TimeInterval?

    public init(configuration: SignalCommandActivationConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func process(
        _ sample: SignalCommandActivationSample
    ) -> SignalCommandActivationEvent {
        let activeConfiguration = configuration.validated()
        guard sample.monotonicSeconds.isFinite,
              lastTimestamp.map({ sample.monotonicSeconds >= $0 }) ?? true
        else {
            reset()
            return .idle
        }
        lastTimestamp = sample.monotonicSeconds

        guard let gesture = sample.gesture,
              sample.confidence.isFinite,
              (0...1).contains(sample.confidence),
              sample.confidence >= activeConfiguration.confidenceThreshold
        else {
            clearCandidate()
            latchedGesture = nil
            return .idle
        }

        if let latchedGesture {
            if latchedGesture == gesture {
                return .waitingForRelease(latchedGesture)
            }
            self.latchedGesture = nil
            clearCandidate()
        }

        if candidate != gesture {
            candidate = gesture
            candidateSince = sample.monotonicSeconds
            return .progressing(gesture: gesture, progress: 0)
        }

        let elapsed = sample.monotonicSeconds - (candidateSince ?? sample.monotonicSeconds)
        let progress = min(max(elapsed / activeConfiguration.holdDuration, 0), 1)
        let cooldownComplete = lastTriggerAt.map {
            sample.monotonicSeconds - $0 >= activeConfiguration.cooldownDuration
        } ?? true

        let holdComplete = elapsed + 1e-9 >= activeConfiguration.holdDuration
        if holdComplete, cooldownComplete {
            lastTriggerAt = sample.monotonicSeconds
            latchedGesture = gesture
            clearCandidate()
            return .triggered(gesture)
        }
        return .progressing(gesture: gesture, progress: progress)
    }

    public mutating func reset() {
        candidate = nil
        candidateSince = nil
        latchedGesture = nil
        lastTriggerAt = nil
        lastTimestamp = nil
    }

    private mutating func clearCandidate() {
        candidate = nil
        candidateSince = nil
    }
}
