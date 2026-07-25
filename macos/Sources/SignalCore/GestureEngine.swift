import Foundation

public enum CommandGesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case one
    case two
    case three
    case four
    case five
    case fist
    case thumbsUp = "thumbs_up"
    case thumbsDown = "thumbs_down"
    case cShape = "c_shape"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .thumbsUp: return "Thumbs Up"
        case .thumbsDown: return "Thumbs Down"
        case .cShape: return "C Shape"
        default: return rawValue.capitalized
        }
    }

    public var symbol: String {
        switch self {
        case .one: return "1.circle"
        case .two: return "2.circle"
        case .three: return "3.circle"
        case .four: return "4.circle"
        case .five: return "hand.raised"
        case .fist: return "hand.point.up.braille"
        case .thumbsUp: return "hand.thumbsup"
        case .thumbsDown: return "hand.thumbsdown"
        case .cShape: return "c.circle"
        }
    }
}

public enum Finger: String, Codable, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
}

public struct GestureFeatures: Equatable, Sendable {
    public var handedness: Handedness
    public var fingerExtension: [Finger: Double]
    public var jointStraightness: [Finger: Double]
    public var thumbVertical: Double
    public var thumbFingerGap: Double
    public var cCurvature: Double
    public var palmFacing: Double
    public var requiredConfidence: Double

    public init(
        handedness: Handedness = .right,
        fingerExtension: [Finger: Double],
        jointStraightness: [Finger: Double] = [:],
        thumbVertical: Double = 0,
        thumbFingerGap: Double = 0,
        cCurvature: Double = 0,
        palmFacing: Double = 1,
        requiredConfidence: Double = 1
    ) {
        self.handedness = handedness
        self.fingerExtension = fingerExtension
        self.jointStraightness = jointStraightness
        self.thumbVertical = thumbVertical
        self.thumbFingerGap = thumbFingerGap
        self.cCurvature = cCurvature
        self.palmFacing = palmFacing
        self.requiredConfidence = requiredConfidence
    }

    public subscript(_ finger: Finger) -> Double { fingerExtension[finger] ?? 0 }
}

public struct GestureCandidate: Equatable, Sendable {
    public var gesture: CommandGesture
    public var confidence: Double

    public init(_ gesture: CommandGesture, confidence: Double) {
        self.gesture = gesture
        self.confidence = confidence
    }
}

public struct CommandGestureClassifier: Sendable {
    public var minimumJointConfidence: Double
    public var minimumGestureConfidence: Double

    public init(minimumJointConfidence: Double = 0.32, minimumGestureConfidence: Double = 0.58) {
        self.minimumJointConfidence = minimumJointConfidence
        self.minimumGestureConfidence = minimumGestureConfidence
    }

    public func classify(_ landmarks: HandLandmarks) -> GestureCandidate? {
        guard let features = extractFeatures(landmarks) else { return nil }
        return classify(features)
    }

    public func classify(_ features: GestureFeatures) -> GestureCandidate? {
        guard features.requiredConfidence >= minimumJointConfidence,
              features.palmFacing >= 0.30 else { return nil }

        let extended = { (finger: Finger) in clamped(features[finger], 0...1) }
        let folded = { (finger: Finger) in 1 - extended(finger) }
        let straight = { (finger: Finger) in
            clamped(features.jointStraightness[finger] ?? features[finger], 0...1)
        }
        let average: ([Double]) -> Double = { values in
            values.reduce(0, +) / Double(max(values.count, 1))
        }

        var scores: [CommandGesture: Double] = [:]
        scores[.one] = average([
            extended(.index), straight(.index),
            folded(.middle), folded(.ring), folded(.little)
        ])
        scores[.two] = average([
            extended(.index), straight(.index), extended(.middle), straight(.middle),
            folded(.ring), folded(.little)
        ])
        scores[.three] = average([
            extended(.index), extended(.middle), extended(.ring),
            folded(.little), straight(.index), straight(.middle)
        ])
        scores[.four] = average([
            folded(.thumb), extended(.index), extended(.middle), extended(.ring), extended(.little),
            straight(.index), straight(.little)
        ])
        scores[.five] = average(Finger.allCases.map(extended) + [.init(features.palmFacing)])
        scores[.fist] = average(Finger.allCases.map(folded))

        let nonThumbFolded = average([folded(.index), folded(.middle), folded(.ring), folded(.little)])
        scores[.thumbsUp] = average([
            extended(.thumb), nonThumbFolded,
            clamped((features.thumbVertical - 0.30) / 0.70, 0...1)
        ])
        scores[.thumbsDown] = average([
            extended(.thumb), nonThumbFolded,
            clamped((-features.thumbVertical - 0.30) / 0.70, 0...1)
        ])

        let partialCurl = average([.index, .middle, .ring, .little].map {
            1 - abs(0.50 - extended($0)) * 2
        })
        let gapScore = 1 - clamped(abs(features.thumbFingerGap - 0.72) / 0.60, 0...1)
        scores[.cShape] = average([
            partialCurl,
            clamped(features.cCurvature, 0...1),
            gapScore,
            folded(.little) * 0.25 + 0.5
        ])

        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        let confidence = clamped(best.value * features.requiredConfidence, 0...1)
        guard confidence >= minimumGestureConfidence else { return nil }
        return GestureCandidate(best.key, confidence: confidence)
    }

    /// Converts raw points into a mirrored, palm-local and scale-normalized feature set.
    public func extractFeatures(_ hand: HandLandmarks) -> GestureFeatures? {
        guard let wrist = hand[.wrist],
              let indexMCP = hand[.indexMCP],
              let middleMCP = hand[.middleMCP],
              let littleMCP = hand[.littleMCP] else { return nil }

        let palmYVector = middleMCP.location - wrist.location
        let palmScale = max(
            indexMCP.location.distance(to: littleMCP.location),
            palmYVector.magnitude,
            0.000_1
        )
        let yAxis = palmYVector * (1 / max(palmYVector.magnitude, 0.000_1))
        var xAxis = Point2D(x: yAxis.y, y: -yAxis.x)
        if hand.handedness == .left { xAxis = xAxis * -1 }

        func local(_ point: Point2D) -> Point2D {
            let delta = point - wrist.location
            return Point2D(
                x: (delta.x * xAxis.x + delta.y * xAxis.y) / palmScale,
                y: (delta.x * yAxis.x + delta.y * yAxis.y) / palmScale
            )
        }

        let chains: [Finger: [HandJoint]] = [
            .thumb: [.thumbCMC, .thumbMP, .thumbIP, .thumbTip],
            .index: [.indexMCP, .indexPIP, .indexDIP, .indexTip],
            .middle: [.middleMCP, .middlePIP, .middleDIP, .middleTip],
            .ring: [.ringMCP, .ringPIP, .ringDIP, .ringTip],
            .little: [.littleMCP, .littlePIP, .littleDIP, .littleTip]
        ]

        var fingerExtension: [Finger: Double] = [:]
        var straightness: [Finger: Double] = [:]
        var usedConfidence: [Double] = [
            wrist.confidence, indexMCP.confidence, middleMCP.confidence, littleMCP.confidence
        ]
        var curvature: [Double] = []

        for (finger, chain) in chains {
            guard let a = hand[chain[0]], let b = hand[chain[1]],
                  let c = hand[chain[2]], let d = hand[chain[3]] else { continue }
            usedConfidence.append(contentsOf: [a.confidence, b.confidence, c.confidence, d.confidence])
            let firstAngle = angleDegrees(a.location, b.location, c.location)
            let secondAngle = angleDegrees(b.location, c.location, d.location)
            let straightScore = clamped((min(firstAngle, secondAngle) - 80) / 95, 0...1)
            let root = local(a.location)
            let tip = local(d.location)
            let reach = d.location.distance(to: a.location) / palmScale
            let directionScore: Double
            if finger == .thumb {
                directionScore = clamped((reach - 0.22) / 0.55, 0...1)
            } else {
                directionScore = clamped((tip.y - root.y - 0.08) / 0.55, 0...1)
            }
            straightness[finger] = straightScore
            fingerExtension[finger] = clamped(straightScore * 0.65 + directionScore * 0.35, 0...1)
            if finger != .thumb {
                curvature.append(clamped((155 - min(firstAngle, secondAngle)) / 65, 0...1))
            }
        }

        guard let thumbTip = hand[.thumbTip], let indexTip = hand[.indexTip] else { return nil }
        let thumbVector = local(thumbTip.location) - local(hand[.thumbCMC]?.location ?? wrist.location)
        let thumbVertical = clamped(thumbVector.y / max(thumbVector.magnitude, 0.000_1), -1...1)
        let gap = thumbTip.location.distance(to: indexTip.location) / palmScale
        let confidence = usedConfidence.sorted().dropFirst(max(0, usedConfidence.count / 5)).first ?? 0

        return GestureFeatures(
            handedness: hand.handedness,
            fingerExtension: fingerExtension,
            jointStraightness: straightness,
            thumbVertical: thumbVertical,
            thumbFingerGap: gap,
            cCurvature: curvature.reduce(0, +) / Double(max(curvature.count, 1)),
            palmFacing: 1,
            requiredConfidence: confidence
        )
    }
}

public enum SignalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case touch
    case command = "commands"
    case hybrid

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public struct CommandContext: Equatable, Sendable {
    public var mode: SignalMode
    public var outputPaused: Bool
    public var pinchActive: Bool
    public var editing: Bool
    public var recording: Bool
    public var permissionOnboarding: Bool
    public var oneCommandEnabledInHybrid: Bool
    public var onePoseStationaryDuration: TimeInterval

    public init(
        mode: SignalMode,
        outputPaused: Bool = false,
        pinchActive: Bool = false,
        editing: Bool = false,
        recording: Bool = false,
        permissionOnboarding: Bool = false,
        oneCommandEnabledInHybrid: Bool = false,
        onePoseStationaryDuration: TimeInterval = 0
    ) {
        self.mode = mode
        self.outputPaused = outputPaused
        self.pinchActive = pinchActive
        self.editing = editing
        self.recording = recording
        self.permissionOnboarding = permissionOnboarding
        self.oneCommandEnabledInHybrid = oneCommandEnabledInHybrid
        self.onePoseStationaryDuration = onePoseStationaryDuration
    }

    public func permits(_ gesture: CommandGesture) -> Bool {
        guard !outputPaused, !pinchActive, !editing, !recording, !permissionOnboarding else {
            return false
        }
        switch mode {
        case .touch:
            return false
        case .command:
            return true
        case .hybrid:
            if gesture != .one { return true }
            return oneCommandEnabledInHybrid && onePoseStationaryDuration >= 0.9
        }
    }
}

public struct ActivationConfiguration: Codable, Equatable, Sendable {
    public var holdDuration = 0.60
    public var cooldown = 0.90
    public var confidenceThreshold = 0.62
    public var confidenceGapGrace = 0.12
    public var repeatWhileHeld = false

    public init() {}
}

public enum ActivationEvent: Equatable, Sendable {
    case idle
    case progressing(gesture: CommandGesture, progress: Double, confidence: Double)
    case triggered(CommandGesture)
    case releaseRequired(CommandGesture)
}

/// Stable-hold, bounded-gap, cooldown and release-gate state machine.
public struct CommandActivationEngine: Sendable {
    public var configuration: ActivationConfiguration
    private var candidate: CommandGesture?
    private var candidateSince: TimeInterval?
    private var gapSince: TimeInterval?
    private var releaseGate: CommandGesture?
    private var lastTriggerAt: TimeInterval?

    public init(configuration: ActivationConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func update(
        candidate newCandidate: GestureCandidate?,
        at timestamp: TimeInterval,
        context: CommandContext
    ) -> ActivationEvent {
        guard let newCandidate, context.permits(newCandidate.gesture) else {
            if let current = candidate, gapSince == nil {
                gapSince = timestamp
                return .progressing(gesture: current, progress: progress(at: timestamp), confidence: 0)
            }
            if let gapSince, timestamp - gapSince <= configuration.confidenceGapGrace,
               let current = candidate {
                return .progressing(gesture: current, progress: progress(at: timestamp), confidence: 0)
            }
            resetCandidate()
            if newCandidate == nil { releaseGate = nil }
            return .idle
        }

        guard newCandidate.confidence >= configuration.confidenceThreshold else {
            if gapSince == nil { gapSince = timestamp }
            if let current = candidate, let gapSince,
               timestamp - gapSince <= configuration.confidenceGapGrace {
                return .progressing(gesture: current, progress: progress(at: timestamp), confidence: newCandidate.confidence)
            }
            resetCandidate()
            return .idle
        }

        gapSince = nil
        if let gated = releaseGate, gated == newCandidate.gesture, !configuration.repeatWhileHeld {
            return .releaseRequired(gated)
        }
        if candidate != newCandidate.gesture {
            candidate = newCandidate.gesture
            candidateSince = timestamp
            return .progressing(gesture: newCandidate.gesture, progress: 0, confidence: newCandidate.confidence)
        }

        let currentProgress = progress(at: timestamp)
        let cooldownSatisfied = lastTriggerAt.map { timestamp - $0 >= configuration.cooldown } ?? true
        if currentProgress >= 1, cooldownSatisfied {
            lastTriggerAt = timestamp
            releaseGate = newCandidate.gesture
            if configuration.repeatWhileHeld {
                candidateSince = timestamp
            }
            return .triggered(newCandidate.gesture)
        }
        return .progressing(
            gesture: newCandidate.gesture,
            progress: currentProgress,
            confidence: newCandidate.confidence
        )
    }

    public mutating func cancel() {
        resetCandidate()
        releaseGate = nil
    }

    private func progress(at timestamp: TimeInterval) -> Double {
        guard let candidateSince else { return 0 }
        return clamped((timestamp - candidateSince) / max(configuration.holdDuration, 0.001), 0...1)
    }

    private mutating func resetCandidate() {
        candidate = nil
        candidateSince = nil
        gapSince = nil
    }
}
