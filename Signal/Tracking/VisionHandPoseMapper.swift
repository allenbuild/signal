import Foundation
@preconcurrency import Vision

public struct VisionMappingResult: Sendable {
    public var observations: [RawHandObservation]
    public var rejectionReasons: [TrackingDegradationReason]

    public var rejectedObservationCount: Int { rejectionReasons.count }

    public init(
        observations: [RawHandObservation],
        rejectionReasons: [TrackingDegradationReason] = []
    ) {
        self.observations = observations
        self.rejectionReasons = rejectionReasons
    }
}

public struct VisionLandmarkMappingOutcome: Sendable {
    public var observation: RawHandObservation?
    public var rejectionReason: TrackingDegradationReason?

    public init(
        observation: RawHandObservation?,
        rejectionReason: TrackingDegradationReason?
    ) {
        self.observation = observation
        self.rejectionReason = rejectionReason
    }
}

public struct VisionLandmarkPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// Framework-independent Vision boundary. Inputs use Vision's normalized
/// lower-left, unmirrored coordinates; output uses Signal's top-left,
/// mirrored preview contract.
public enum VisionLandmarkBoundary {
    public static func map(
        _ points: [LandmarkName: VisionLandmarkPoint],
        timestamp: MonotonicTimestamp,
        chirality: HandChirality,
        minimumConfidence: Double
    ) -> RawHandObservation? {
        mapWithReason(
            points,
            timestamp: timestamp,
            chirality: chirality,
            minimumConfidence: minimumConfidence
        ).observation
    }

    public static func mapWithReason(
        _ points: [LandmarkName: VisionLandmarkPoint],
        timestamp: MonotonicTimestamp,
        chirality: HandChirality,
        minimumConfidence: Double
    ) -> VisionLandmarkMappingOutcome {
        guard timestamp.rawValue.isFinite else {
            return .init(observation: nil, rejectionReason: .invalidTimestamp)
        }
        var landmarks = HandLandmarks()
        for (name, point) in points {
            guard point.x.isFinite, point.y.isFinite, point.confidence.isFinite,
                  (0 ... 1).contains(point.x), (0 ... 1).contains(point.y),
                  (0 ... 1).contains(point.confidence) else { continue }
            landmarks[name] = LandmarkSample(
                position: Point2D(x: 1 - point.x, y: 1 - point.y),
                confidence: point.confidence
            )
        }

        switch PalmGeometryEstimator.evaluate(
            landmarks: landmarks,
            minimumConfidence: minimumConfidence
        ) {
        case .valid:
            break
        case .palmAnchorsMissing:
            return .init(observation: nil, rejectionReason: .palmAnchorsMissing)
        case .invalidPalmScale:
            return .init(observation: nil, rejectionReason: .invalidPalmScale)
        }

        let confidences = landmarks.samples.values.map(\.confidence).sorted()
        guard !confidences.isEmpty else {
            return .init(observation: nil, rejectionReason: .visionFailure)
        }
        let middle = confidences.count / 2
        let median = confidences.count.isMultiple(of: 2)
            ? (confidences[middle - 1] + confidences[middle]) / 2
            : confidences[middle]
        return .init(
            observation: RawHandObservation(
                timestamp: timestamp,
                landmarks: landmarks,
                observationConfidence: median,
                chirality: chirality
            ),
            rejectionReason: nil
        )
    }
}

public struct VisionHandPoseMapper: Sendable {
    public var minimumConfidence: Double

    public init(minimumConfidence: Double = GestureTuning.safeDefaults.minimumLandmarkConfidence) {
        self.minimumConfidence = Self.validatedConfidence(minimumConfidence)
    }

    public func map(
        _ observations: [VNHumanHandPoseObservation],
        timestamp: MonotonicTimestamp
    ) -> VisionMappingResult {
        var mapped: [RawHandObservation] = []
        mapped.reserveCapacity(min(observations.count, 2))
        var rejectionReasons: [TrackingDegradationReason] = []
        rejectionReasons.reserveCapacity(observations.count)

        for observation in observations {
            do {
                let outcome = try mapWithReason(observation, timestamp: timestamp)
                guard let hand = outcome.observation else {
                    rejectionReasons.append(outcome.rejectionReason ?? .visionFailure)
                    continue
                }
                mapped.append(hand)
            } catch {
                rejectionReasons.append(.visionFailure)
            }
        }

        return VisionMappingResult(
            observations: mapped,
            rejectionReasons: rejectionReasons
        )
    }

    public func map(
        _ observation: VNHumanHandPoseObservation,
        timestamp: MonotonicTimestamp
    ) throws -> RawHandObservation? {
        try mapWithReason(observation, timestamp: timestamp).observation
    }

    public func mapWithReason(
        _ observation: VNHumanHandPoseObservation,
        timestamp: MonotonicTimestamp
    ) throws -> VisionLandmarkMappingOutcome {
        guard timestamp.rawValue.isFinite else {
            return .init(observation: nil, rejectionReason: .invalidTimestamp)
        }
        let recognized = try observation.recognizedPoints(.all)
        var points: [LandmarkName: VisionLandmarkPoint] = [:]
        points.reserveCapacity(LandmarkName.allCases.count)

        for (visionName, projectName) in Self.jointMap {
            guard let point = recognized[visionName] else { continue }
            points[projectName] = VisionLandmarkPoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        return VisionLandmarkBoundary.mapWithReason(
            points,
            timestamp: timestamp,
            chirality: Self.mapChirality(observation.chirality),
            minimumConfidence: minimumConfidence
        )
    }

    private static let jointMap: [(VNHumanHandPoseObservation.JointName, LandmarkName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP),
        (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP),
        (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP),
        (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP),
        (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP),
        (.littleDIP, .littleDIP), (.littleTip, .littleTip)
    ]

    private static func mapChirality(_ chirality: VNChirality) -> HandChirality {
        switch chirality {
        case .left: .left
        case .right: .right
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }

    private static func validatedConfidence(_ value: Double) -> Double {
        guard value.isFinite else { return GestureTuning.safeDefaults.minimumLandmarkConfidence }
        return min(max(value, 0), 1)
    }
}
