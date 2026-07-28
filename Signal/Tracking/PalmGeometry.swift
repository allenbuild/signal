import Foundation

struct PalmGeometry: Equatable, Sendable {
    var center: Point2D
    var width: Double
    var scaleSource: PalmScaleSource
    var anchorConfidence: Double
}

enum PalmGeometryEvaluation: Equatable, Sendable {
    case valid(PalmGeometry)
    case palmAnchorsMissing
    case invalidPalmScale
}

enum PalmGeometryEstimator {
    static let minimumUsableWidth = 0.02
    static let maximumUsableWidth = 0.80

    static func estimate(
        landmarks: HandLandmarks,
        minimumConfidence: Double
    ) -> PalmGeometry? {
        guard case let .valid(geometry) = evaluate(
            landmarks: landmarks,
            minimumConfidence: minimumConfidence
        ) else {
            return nil
        }
        return geometry
    }

    static func evaluate(
        landmarks: HandLandmarks,
        minimumConfidence: Double
    ) -> PalmGeometryEvaluation {
        guard let wrist = reliable(.wrist, in: landmarks, minimumConfidence: minimumConfidence) else {
            return .palmAnchorsMissing
        }

        let index = reliable(.indexMCP, in: landmarks, minimumConfidence: minimumConfidence)
        let middle = reliable(.middleMCP, in: landmarks, minimumConfidence: minimumConfidence)
        let ring = reliable(.ringMCP, in: landmarks, minimumConfidence: minimumConfidence)
        let little = reliable(.littleMCP, in: landmarks, minimumConfidence: minimumConfidence)

        let primaryWidth = index.flatMap { index in
            little.map { TrackingMath.distance(index.position, $0.position) }
        }
        let fallbackWidth = middle.map {
            0.90 * TrackingMath.distance(wrist.position, $0.position)
        }

        let scale: (width: Double, source: PalmScaleSource)
        if let primaryWidth, isUsable(width: primaryWidth) {
            scale = (primaryWidth, .indexToLittleMCP)
        } else if let fallbackWidth, isUsable(width: fallbackWidth) {
            // A confidently detected but geometrically collapsed primary pair
            // must not hide a usable wrist-to-middle scale for this frame.
            scale = (fallbackWidth, .wristToMiddleMCP)
        } else if primaryWidth != nil || fallbackWidth != nil {
            return .invalidPalmScale
        } else {
            return .palmAnchorsMissing
        }

        var weightedX = wrist.position.x * 2
        var weightedY = wrist.position.y * 2
        var totalWeight = 2.0
        var confidences = [wrist.confidence]

        for sample in [index, middle, ring, little].compactMap({ $0 }) {
            weightedX += sample.position.x
            weightedY += sample.position.y
            totalWeight += 1
            confidences.append(sample.confidence)
        }

        let center = Point2D(x: weightedX / totalWeight, y: weightedY / totalWeight)
        guard TrackingMath.isFinite(center) else { return .invalidPalmScale }

        return .valid(PalmGeometry(
            center: center,
            width: scale.width,
            scaleSource: scale.source,
            anchorConfidence: confidences.min() ?? 0
        ))
    }

    private static func isUsable(width: Double) -> Bool {
        width.isFinite
            && width >= minimumUsableWidth
            && width <= maximumUsableWidth
    }

    static func reliable(
        _ name: LandmarkName,
        in landmarks: HandLandmarks,
        minimumConfidence: Double
    ) -> LandmarkSample? {
        guard let sample = landmarks[name],
              sample.confidence.isFinite,
              sample.confidence >= minimumConfidence,
              TrackingMath.isFinite(sample.position) else {
            return nil
        }
        return sample
    }
}
