import Foundation

public enum InputMouseButton: Int, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case left
    case right
    case other
}

public enum InputMouseEventKind: String, Codable, Equatable, Sendable {
    case moved
    case leftDown
    case leftUp
    case leftDragged
    case rightDown
    case rightUp
    case otherDown
    case otherUp
    case otherDragged
}

public struct InputModifierFlags: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
}

public enum LowLevelInputEvent: Equatable, Sendable {
    case mouse(
        kind: InputMouseEventKind,
        position: Point2D,
        button: InputMouseButton,
        clickState: Int64
    )
    case scroll(dx: Int32, dy: Int32)
    case key(keyCode: UInt16, isDown: Bool, modifiers: InputModifierFlags)
}

public struct InputDisplay: Equatable, Sendable {
    public var id: UInt32
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(id: UInt32, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.id = id
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var isDrawable: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
            && minX < maxX && minY < maxY
    }
}

public protocol InputEventBackend: AnyObject, Sendable {
    var marker: Int64 { get }
    var isHealthy: Bool { get }
    func currentCursorLocation() -> Point2D?
    func activeDisplays() -> [InputDisplay]
    func isPhysicalButtonPressed(_ button: InputMouseButton) -> Bool
    func physicalModifierFlags() -> InputModifierFlags

    /// Must construct the complete batch before posting its first event.
    /// `true` means construction and fire-and-forget submission succeeded; it
    /// does not claim WindowServer delivery.
    func post(_ events: [LowLevelInputEvent]) -> Bool
}

public protocol InputTrustProviding: AnyObject, Sendable {
    var isAccessibilityTrusted: Bool { get }
    var canPostEvents: Bool { get }
}

public protocol InputMonotonicClock: AnyObject, Sendable {
    var now: TimeInterval { get }
}

public final class SystemInputMonotonicClock: InputMonotonicClock, @unchecked Sendable {
    public init() {}

    public var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
