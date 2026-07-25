import Foundation

public enum TouchState: String, Codable, Equatable, Sendable {
    case idle
    case pointer
    case pinchPending
    case verticalLocked
    case horizontalLocked
    case cancelled
}

public enum TouchOutput: Equatable, Sendable {
    case pointer(delta: Point2D)
    case click
    case scroll(delta: Double)
    case zoom(steps: Int)
    case state(TouchState)
}

public struct TouchConfiguration: Codable, Equatable, Sendable {
    public var pointerSensitivity = 620.0
    public var pointerSmoothing = 0.45
    public var pointerAcceleration = 1.35
    public var pointerDeadZone = 0.025
    public var invertX = false
    public var invertY = false
    public var clickMaximumDuration = 0.28
    public var clickMovementThreshold = 0.16
    public var axisMinimumHold = 0.12
    public var axisLockThreshold = 0.20
    public var dominanceRatio = 1.35
    public var scrollGain = 900.0
    public var scrollInverted = false
    public var zoomGain = 8.0
    public var zoomInverted = false
    public var pinchCloseThreshold = 0.24
    public var pinchOpenThreshold = 0.34
    public var maximumFrameAge = 0.35
    public var allowSlowStationaryClick = false

    public init() {}
}

public struct TouchFrame: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var frameAge: TimeInterval
    public var trackingValid: Bool
    public var pointerPose: Bool
    public var pinchDistance: Double
    public var handCenter: Point2D
    public var palmScale: Double

    public init(
        timestamp: TimeInterval,
        frameAge: TimeInterval = 0,
        trackingValid: Bool = true,
        pointerPose: Bool = false,
        pinchDistance: Double = 1,
        handCenter: Point2D = .zero,
        palmScale: Double = 1
    ) {
        self.timestamp = timestamp
        self.frameAge = frameAge
        self.trackingValid = trackingValid
        self.pointerPose = pointerPose
        self.pinchDistance = pinchDistance
        self.handCenter = handCenter
        self.palmScale = max(palmScale, 0.000_1)
    }
}

/// Pure deterministic touch transaction engine. It never posts operating-system events.
public struct TouchEngine: Sendable {
    public private(set) var state: TouchState = .idle
    public var configuration: TouchConfiguration

    private var pinchIsClosed = false
    private var pinchStartedAt: TimeInterval?
    private var pinchOrigin: Point2D?
    private var lastPinchCenter: Point2D?
    private var pointerAnchor: Point2D?
    private var lastPointerDelta = Point2D.zero
    private var lastTimestamp: TimeInterval?
    private var zoomRemainder = 0.0

    public init(configuration: TouchConfiguration = .init()) {
        self.configuration = configuration
    }

    public var isPinchActive: Bool {
        switch state {
        case .pinchPending, .verticalLocked, .horizontalLocked: return true
        default: return false
        }
    }

    public mutating func process(_ frame: TouchFrame, outputEnabled: Bool = true) -> [TouchOutput] {
        guard outputEnabled, frame.trackingValid, frame.frameAge <= configuration.maximumFrameAge else {
            return cancel(reanchor: true)
        }

        let nowClosed = pinchIsClosed
            ? frame.pinchDistance < configuration.pinchOpenThreshold
            : frame.pinchDistance <= configuration.pinchCloseThreshold

        if nowClosed && !pinchIsClosed {
            pinchIsClosed = true
            pinchStartedAt = frame.timestamp
            pinchOrigin = frame.handCenter
            lastPinchCenter = frame.handCenter
            lastTimestamp = frame.timestamp
            pointerAnchor = nil
            zoomRemainder = 0
            state = .pinchPending
            return [.state(.pinchPending)]
        }

        if !nowClosed && pinchIsClosed {
            pinchIsClosed = false
            return finishPinch(frame)
        }

        if nowClosed {
            return updatePinch(frame)
        }

        return updatePointer(frame)
    }

    public mutating func cancel(reanchor: Bool = true) -> [TouchOutput] {
        let hadTransaction = isPinchActive || pinchIsClosed
        pinchIsClosed = false
        pinchStartedAt = nil
        pinchOrigin = nil
        lastPinchCenter = nil
        lastTimestamp = nil
        zoomRemainder = 0
        if reanchor {
            pointerAnchor = nil
            lastPointerDelta = .zero
        }
        state = hadTransaction ? .cancelled : .idle
        return hadTransaction ? [.state(.cancelled)] : []
    }

    private mutating func finishPinch(_ frame: TouchFrame) -> [TouchOutput] {
        defer {
            pinchStartedAt = nil
            pinchOrigin = nil
            lastPinchCenter = nil
            lastTimestamp = nil
            zoomRemainder = 0
            pointerAnchor = nil
            state = .idle
        }
        guard state == .pinchPending,
              let started = pinchStartedAt,
              let origin = pinchOrigin else {
            return [.state(.idle)]
        }
        let duration = max(0, frame.timestamp - started)
        let movement = frame.handCenter.distance(to: origin) / frame.palmScale
        let quickEnough = duration <= configuration.clickMaximumDuration
        if movement <= configuration.clickMovementThreshold &&
            (quickEnough || configuration.allowSlowStationaryClick) {
            return [.click, .state(.idle)]
        }
        return [.state(.idle)]
    }

    private mutating func updatePinch(_ frame: TouchFrame) -> [TouchOutput] {
        guard let origin = pinchOrigin,
              let previous = lastPinchCenter,
              let started = pinchStartedAt else {
            return cancel()
        }
        let displacement = (frame.handCenter - origin) * (1 / frame.palmScale)
        let increment = (frame.handCenter - previous) * (1 / frame.palmScale)
        let duration = frame.timestamp - started
        let dt = max(frame.timestamp - (lastTimestamp ?? frame.timestamp), 1.0 / 120.0)
        lastPinchCenter = frame.handCenter
        lastTimestamp = frame.timestamp

        if state == .pinchPending,
           duration >= configuration.axisMinimumHold,
           displacement.magnitude >= configuration.axisLockThreshold {
            let verticalRatio = abs(displacement.y) / max(abs(displacement.x), 0.000_1)
            let horizontalRatio = abs(displacement.x) / max(abs(displacement.y), 0.000_1)
            if verticalRatio >= configuration.dominanceRatio {
                state = .verticalLocked
                return [.state(.verticalLocked)]
            } else if horizontalRatio >= configuration.dominanceRatio {
                state = .horizontalLocked
                return [.state(.horizontalLocked)]
            }
        }

        switch state {
        case .verticalLocked:
            var amount = increment.y * configuration.scrollGain / max(dt * 60, 1)
            if !configuration.scrollInverted { amount *= -1 }
            return abs(amount) < 0.05 ? [] : [.scroll(delta: amount)]
        case .horizontalLocked:
            var amount = increment.x * configuration.zoomGain
            if configuration.zoomInverted { amount *= -1 }
            zoomRemainder += amount
            let steps = Int(zoomRemainder.rounded(.towardZero))
            if steps != 0 {
                zoomRemainder -= Double(steps)
                return [.zoom(steps: steps)]
            }
            return []
        default:
            return []
        }
    }

    private mutating func updatePointer(_ frame: TouchFrame) -> [TouchOutput] {
        guard frame.pointerPose else {
            pointerAnchor = nil
            lastPointerDelta = .zero
            if state != .idle {
                state = .idle
                return [.state(.idle)]
            }
            return []
        }
        guard let anchor = pointerAnchor else {
            pointerAnchor = frame.handCenter
            lastTimestamp = frame.timestamp
            state = .pointer
            return [.state(.pointer)]
        }

        var normalized = (frame.handCenter - anchor) * (1 / frame.palmScale)
        pointerAnchor = frame.handCenter
        normalized.x *= configuration.invertX ? 1 : -1 // mirror camera X naturally
        normalized.y *= configuration.invertY ? 1 : -1
        let magnitude = normalized.magnitude
        guard magnitude > configuration.pointerDeadZone else { return [] }

        let usefulMagnitude = magnitude - configuration.pointerDeadZone
        let accelerated = pow(usefulMagnitude, configuration.pointerAcceleration)
        let raw = normalized * (accelerated / max(magnitude, 0.000_1) * configuration.pointerSensitivity)
        let alpha = clamped(1 - configuration.pointerSmoothing, 0.05...1)
        let filtered = raw * alpha + lastPointerDelta * (1 - alpha)
        lastPointerDelta = filtered
        state = .pointer
        return [.pointer(delta: filtered)]
    }
}
