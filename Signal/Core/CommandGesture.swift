import Foundation

/// Stable semantic identifiers for Signal's programmable command poses.
///
/// Control gestures intentionally do not appear here. In particular, an
/// index-only hand may be `.one` for command recognition while the existing
/// Control engine continues to interpret the same geometry as pointer input.
public enum CommandGesture: String, CaseIterable, Codable, Equatable, Sendable {
    case one
    case two
    case three
    case four
    case thumbsUp = "thumbs_up"
    case thumbsDown = "thumbs_down"
    case cShape = "c_shape"
    case fist
}

/// A single mutually-exclusive command-pose observation.
///
/// Activation timing, cooldowns, command lookup, and execution belong to
/// higher layers. This value contains geometry evidence only.
public struct CommandGestureCandidate: Codable, Equatable, Sendable {
    public var gesture: CommandGesture
    public var confidence: Double
    public var requiredJointConfidence: Double

    public init(
        gesture: CommandGesture,
        confidence: Double,
        requiredJointConfidence: Double
    ) {
        self.gesture = gesture
        self.confidence = confidence
        self.requiredJointConfidence = requiredJointConfidence
    }
}
