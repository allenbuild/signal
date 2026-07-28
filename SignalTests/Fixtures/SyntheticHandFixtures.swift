import Foundation
@testable import Signal

enum FixturePose {
    case openPalm
    case fist
    case pointer
    case scroll
    case pinch(ratio: Double)
}

struct SyntheticHand {
    private(set) var localPoints: [LandmarkName: Point2D]
    private(set) var confidences: [LandmarkName: Double]
    var observationConfidence: Double = 0.95
    var chirality: HandChirality = .right

    static func pose(_ pose: FixturePose) -> Self {
        var points = openPalmPoints

        switch pose {
        case .openPalm:
            break
        case .fist:
            applyFoldedFingerOverrides(to: &points, fingers: [.index, .middle, .ring, .little])
        case .pointer:
            applyFoldedFingerOverrides(to: &points, fingers: [.middle, .ring, .little])
        case .scroll:
            applyFoldedFingerOverrides(to: &points, fingers: [.ring, .little])
        case let .pinch(ratio):
            // Pinch fixtures intentionally fold every non-thumb finger. This
            // is the adversarial geometry that previously became a fist even
            // when the thumb and middle fingertip were touching. Click,
            // scroll, and zoom must depend on the thumb-middle pair, never on
            // the index fingertip or on an extended-index pose.
            applyFoldedFingerOverrides(to: &points, fingers: [.index, .middle, .ring, .little])
            points[.thumbCMC] = Point2D(x: -0.30, y: 0.25)
            points[.thumbMP] = Point2D(x: -0.52, y: 0.58)
            points[.thumbIP] = Point2D(x: -0.10, y: 0.70)
            let middleTip = points[.middleTip] ?? Point2D(x: 0.03, y: 0.78)
            points[.thumbTip] = Point2D(x: middleTip.x + ratio, y: middleTip.y)
        }

        return Self(
            localPoints: points,
            confidences: Dictionary(uniqueKeysWithValues: LandmarkName.allCases.map { ($0, 0.95) })
        )
    }

    func translatedLocal(dx: Double, dy: Double) -> Self {
        transforming { Point2D(x: $0.x + dx, y: $0.y + dy) }
    }

    func scaledLocal(_ factor: Double) -> Self {
        transforming { Point2D(x: $0.x * factor, y: $0.y * factor) }
    }

    func rotatedLocal(_ radians: Double) -> Self {
        let cosine = cos(radians)
        let sine = sin(radians)
        return transforming {
            Point2D(
                x: $0.x * cosine - $0.y * sine,
                y: $0.x * sine + $0.y * cosine
            )
        }
    }

    func reflectedAboutPreviewMidline() -> Self {
        var result = transforming { Point2D(x: -$0.x, y: $0.y) }
        switch chirality {
        case .left: result.chirality = .right
        case .right: result.chirality = .left
        case .unknown: result.chirality = .unknown
        }
        return result
    }

    func withConfidence(_ confidence: Double, for name: LandmarkName) -> Self {
        var result = self
        result.confidences[name] = confidence
        return result
    }

    func withLocalPoint(_ point: Point2D, for name: LandmarkName) -> Self {
        var result = self
        result.localPoints[name] = point
        return result
    }

    /// Changes only the thumb tip so its palm-normalized distance from the
    /// middle fingertip is exactly `ratio`. Palm anchors and the index finger
    /// remain untouched, making this suitable for closure-only regressions.
    func withMiddleThumbDistance(_ ratio: Double) -> Self {
        guard let middleTip = localPoints[.middleTip] else { return self }
        return withLocalPoint(
            Point2D(x: middleTip.x + ratio, y: middleTip.y),
            for: .thumbTip
        )
    }

    /// Translates only the two fingertips participating in the pinch. A
    /// wrist/palm scroll anchor must ignore this motion completely.
    func movingMiddleThumbTips(dx: Double, dy: Double) -> Self {
        var result = self
        for name in [LandmarkName.thumbTip, .middleTip] {
            guard let point = result.localPoints[name] else { continue }
            result.localPoints[name] = Point2D(x: point.x + dx, y: point.y + dy)
        }
        return result
    }

    /// Restores the canonical extended index without changing the middle-thumb
    /// pair. This proves that pinch priority suppresses an otherwise valid
    /// pointer pose and that the index is not a click input.
    func withIndexExtended() -> Self {
        var result = self
        for name in [LandmarkName.indexMCP, .indexPIP, .indexDIP, .indexTip] {
            result.localPoints[name] = Self.openPalmPoints[name]
        }
        return result
    }

    func without(_ name: LandmarkName) -> Self {
        var result = self
        result.localPoints[name] = nil
        result.confidences[name] = nil
        return result
    }

    func withObservationConfidence(_ confidence: Double) -> Self {
        var result = self
        result.observationConfidence = confidence
        return result
    }

    func withChirality(_ chirality: HandChirality) -> Self {
        var result = self
        result.chirality = chirality
        return result
    }

    func landmarks() -> HandLandmarks {
        var result = HandLandmarks()
        for name in LandmarkName.allCases {
            guard let local = localPoints[name], let confidence = confidences[name] else { continue }
            result[name] = LandmarkSample(
                position: Point2D(x: 0.50 + 0.14 * local.x, y: 0.20 + 0.14 * local.y),
                confidence: confidence
            )
        }
        return result
    }

    func rawObservation(at time: Double) -> RawHandObservation {
        RawHandObservation(
            timestamp: MonotonicTimestamp(rawValue: time),
            landmarks: landmarks(),
            observationConfidence: observationConfidence,
            chirality: chirality
        )
    }

    func tracked(
        id: UInt64 = 1,
        at time: Double,
        associationCertain: Bool = true,
        missingDuration: TimeInterval = 0
    ) -> TrackedHandSnapshot {
        let values = landmarks()
        let width: Double
        if let index = values[.indexMCP]?.position, let little = values[.littleMCP]?.position {
            width = hypot(index.x - little.x, index.y - little.y)
        } else if let wrist = values[.wrist]?.position, let middle = values[.middleMCP]?.position {
            width = 0.90 * hypot(wrist.x - middle.x, wrist.y - middle.y)
        } else {
            width = 0
        }
        return TrackedHandSnapshot(
            id: HandTrackID(rawValue: id),
            timestamp: MonotonicTimestamp(rawValue: time),
            rawLandmarks: values,
            filteredLandmarks: values,
            palmWidth: width,
            palmScaleSource: width > 0 ? .indexToLittleMCP : .unavailable,
            confidence: observationConfidence,
            velocity: Point2D(x: 0, y: 0),
            missingDuration: missingDuration,
            associationCertain: associationCertain
        )
    }

    private func transforming(_ transform: (Point2D) -> Point2D) -> Self {
        var result = self
        result.localPoints = localPoints.mapValues(transform)
        return result
    }

    private enum Finger {
        case index, middle, ring, little
    }

    private static func applyFoldedFingerOverrides(
        to points: inout [LandmarkName: Point2D],
        fingers: [Finger]
    ) {
        for finger in fingers {
            switch finger {
            case .index:
                points[.indexPIP] = Point2D(x: -0.48, y: 1.08)
                points[.indexDIP] = Point2D(x: -0.30, y: 0.93)
                points[.indexTip] = Point2D(x: -0.26, y: 0.68)
            case .middle:
                points[.middlePIP] = Point2D(x: -0.10, y: 1.18)
                points[.middleDIP] = Point2D(x: 0.05, y: 1.02)
                points[.middleTip] = Point2D(x: 0.03, y: 0.78)
            case .ring:
                points[.ringPIP] = Point2D(x: 0.24, y: 1.12)
                points[.ringDIP] = Point2D(x: 0.37, y: 0.96)
                points[.ringTip] = Point2D(x: 0.33, y: 0.74)
            case .little:
                points[.littlePIP] = Point2D(x: 0.53, y: 1.03)
                points[.littleDIP] = Point2D(x: 0.65, y: 0.88)
                points[.littleTip] = Point2D(x: 0.59, y: 0.69)
            }
        }
    }

    private static let openPalmPoints: [LandmarkName: Point2D] = [
        .wrist: Point2D(x: 0.00, y: 0.00),
        .thumbCMC: Point2D(x: -0.30, y: 0.25),
        .thumbMP: Point2D(x: -0.65, y: 0.42),
        .thumbIP: Point2D(x: -0.92, y: 0.55),
        .thumbTip: Point2D(x: -1.15, y: 0.68),
        .indexMCP: Point2D(x: -0.50, y: 0.80),
        .indexPIP: Point2D(x: -0.52, y: 1.28),
        .indexDIP: Point2D(x: -0.53, y: 1.62),
        .indexTip: Point2D(x: -0.54, y: 1.94),
        .middleMCP: Point2D(x: -0.12, y: 0.91),
        .middlePIP: Point2D(x: -0.12, y: 1.45),
        .middleDIP: Point2D(x: -0.12, y: 1.82),
        .middleTip: Point2D(x: -0.12, y: 2.15),
        .ringMCP: Point2D(x: 0.22, y: 0.87),
        .ringPIP: Point2D(x: 0.26, y: 1.35),
        .ringDIP: Point2D(x: 0.28, y: 1.68),
        .ringTip: Point2D(x: 0.30, y: 1.98),
        .littleMCP: Point2D(x: 0.50, y: 0.80),
        .littlePIP: Point2D(x: 0.57, y: 1.19),
        .littleDIP: Point2D(x: 0.61, y: 1.45),
        .littleTip: Point2D(x: 0.66, y: 1.68)
    ]
}

func trackingFrame(
    time: Double,
    hands: [TrackedHandSnapshot],
    quality: TrackingQuality? = nil,
    degradationReason: TrackingDegradationReason? = nil
) -> TrackingSnapshot {
    TrackingSnapshot(
        timestamp: MonotonicTimestamp(rawValue: time),
        hands: hands,
        quality: quality ?? (hands.isEmpty ? .absent : .good),
        diagnostics: .zero,
        degradationReason: degradationReason
    )
}

func gestureTestTuning() -> GestureTuning {
    var tuning = GestureTuning.safeDefaults
    tuning.pinchCloseRatio = 0.22
    tuning.pinchOpenRatio = 0.32
    tuning.pinchIntentRatio = 0.40
    tuning.pointerDeadZone = 0
    tuning.pointerSensitivity = 100
    tuning.pointerAcceleration = 0
    tuning.pointerMaximumDelta = 100
    tuning.pinchScrollActivationDisplacement = 0.06
    tuning.pinchScrollHoldDuration = 0.18
    tuning.scrollDeadZone = 0.01
    tuning.scrollSensitivityX = 100
    tuning.scrollSensitivityY = 100
    tuning.scrollAcceleration = 0
    tuning.scrollMaximumDelta = 100
    tuning.naturalScrolling = false
    tuning.zoomSensitivity = 1
    tuning.zoomDeadZoneFraction = 0.02
    return tuning
}

func zoomHands(time: Double, ratio: Double, halfSeparation: Double) -> [TrackedHandSnapshot] {
    [
        SyntheticHand.pose(.pinch(ratio: ratio))
            .translatedLocal(dx: -halfSeparation, dy: 0)
            .tracked(id: 11, at: time),
        SyntheticHand.pose(.pinch(ratio: ratio))
            .translatedLocal(dx: halfSeparation, dy: 0)
            .tracked(id: 22, at: time)
    ]
}
