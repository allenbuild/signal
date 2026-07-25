import Foundation

public struct Point2D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public static func - (lhs: Self, rhs: Self) -> Self {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func * (lhs: Self, rhs: Double) -> Self {
        Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public var magnitude: Double { hypot(x, y) }

    public func distance(to other: Self) -> Double {
        (self - other).magnitude
    }
}

public enum Handedness: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

public enum HandJoint: String, Codable, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

public struct JointSample: Codable, Equatable, Sendable {
    public var location: Point2D
    public var confidence: Double

    public init(_ location: Point2D, confidence: Double = 1) {
        self.location = location
        self.confidence = confidence
    }
}

public struct HandLandmarks: Codable, Equatable, Sendable {
    public var handedness: Handedness
    public var joints: [HandJoint: JointSample]
    public var timestamp: TimeInterval

    public init(
        handedness: Handedness,
        joints: [HandJoint: JointSample],
        timestamp: TimeInterval = 0
    ) {
        self.handedness = handedness
        self.joints = joints
        self.timestamp = timestamp
    }

    public subscript(_ joint: HandJoint) -> JointSample? { joints[joint] }
}

public func clamped(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

public func angleDegrees(_ a: Point2D, _ b: Point2D, _ c: Point2D) -> Double {
    let ba = a - b
    let bc = c - b
    let denominator = max(ba.magnitude * bc.magnitude, 0.000_001)
    let cosine = clamped((ba.x * bc.x + ba.y * bc.y) / denominator, -1...1)
    return acos(cosine) * 180 / .pi
}
