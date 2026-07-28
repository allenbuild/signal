import Foundation

public struct MonotonicTimestamp: RawRepresentable, Comparable, Codable, Equatable, Hashable, Sendable {
    public var rawValue: Double

    public init(rawValue: Double) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func duration(since earlier: Self) -> TimeInterval {
        rawValue - earlier.rawValue
    }
}

public struct Point2D: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum LandmarkName: Int, CaseIterable, Codable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

public struct LandmarkSample: Codable, Equatable, Sendable {
    public var position: Point2D
    public var confidence: Double

    public init(position: Point2D, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}

public struct HandLandmarks: Codable, Equatable, Sendable {
    public var samples: [LandmarkName: LandmarkSample]

    public init(samples: [LandmarkName: LandmarkSample] = [:]) {
        self.samples = samples
    }

    public subscript(_ name: LandmarkName) -> LandmarkSample? {
        get { samples[name] }
        set { samples[name] = newValue }
    }
}

public enum HandChirality: String, Codable, Equatable, Sendable {
    case left, right, unknown
}

public struct HandTrackID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct RawHandObservation: Codable, Equatable, Sendable {
    public var timestamp: MonotonicTimestamp
    public var landmarks: HandLandmarks
    public var observationConfidence: Double
    public var chirality: HandChirality

    public init(
        timestamp: MonotonicTimestamp,
        landmarks: HandLandmarks,
        observationConfidence: Double,
        chirality: HandChirality = .unknown
    ) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.observationConfidence = observationConfidence
        self.chirality = chirality
    }
}

public enum PalmScaleSource: String, Codable, Equatable, Sendable {
    case indexToLittleMCP, wristToMiddleMCP, unavailable
}

public struct TrackedHandSnapshot: Codable, Equatable, Sendable {
    public var id: HandTrackID
    public var timestamp: MonotonicTimestamp
    public var rawLandmarks: HandLandmarks
    public var filteredLandmarks: HandLandmarks
    public var palmWidth: Double
    public var palmScaleSource: PalmScaleSource
    public var confidence: Double
    public var velocity: Point2D
    public var missingDuration: TimeInterval
    public var associationCertain: Bool

    public init(
        id: HandTrackID,
        timestamp: MonotonicTimestamp,
        rawLandmarks: HandLandmarks,
        filteredLandmarks: HandLandmarks,
        palmWidth: Double,
        palmScaleSource: PalmScaleSource,
        confidence: Double,
        velocity: Point2D,
        missingDuration: TimeInterval,
        associationCertain: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawLandmarks = rawLandmarks
        self.filteredLandmarks = filteredLandmarks
        self.palmWidth = palmWidth
        self.palmScaleSource = palmScaleSource
        self.confidence = confidence
        self.velocity = velocity
        self.missingDuration = missingDuration
        self.associationCertain = associationCertain
    }
}

public enum TrackingQuality: String, Codable, Equatable, Sendable {
    case absent, degraded, good
}

public enum TrackingDegradationReason: String, Codable, Equatable, Sendable {
    case staleFrame
    case noHandDetected
    case palmAnchorsMissing
    case invalidPalmScale
    case associationAmbiguous
    case handIdentityLost
    case lowRequiredJointConfidence
    case poseAmbiguity
    case invalidTimestamp
    case visionFailure
}

public struct TrackingDiagnostics: Codable, Equatable, Sendable {
    public var captureFPS: Double
    public var processedFPS: Double
    public var droppedFrames: UInt64
    public var visionLatencyMilliseconds: Double
    public var endToEndLatencyMilliseconds: Double

    public init(
        captureFPS: Double,
        processedFPS: Double,
        droppedFrames: UInt64,
        visionLatencyMilliseconds: Double,
        endToEndLatencyMilliseconds: Double
    ) {
        self.captureFPS = captureFPS
        self.processedFPS = processedFPS
        self.droppedFrames = droppedFrames
        self.visionLatencyMilliseconds = visionLatencyMilliseconds
        self.endToEndLatencyMilliseconds = endToEndLatencyMilliseconds
    }

    public static let zero = Self(
        captureFPS: 0,
        processedFPS: 0,
        droppedFrames: 0,
        visionLatencyMilliseconds: 0,
        endToEndLatencyMilliseconds: 0
    )
}

public struct TrackingSnapshot: Codable, Equatable, Sendable {
    /// Capture lease that produced this snapshot. Zero is reserved for
    /// synthetic/test snapshots that are not tied to a live camera run.
    public var captureGeneration: UInt64
    public var timestamp: MonotonicTimestamp
    public var hands: [TrackedHandSnapshot]
    public var quality: TrackingQuality
    public var diagnostics: TrackingDiagnostics
    public var degradationReason: TrackingDegradationReason?

    public init(
        captureGeneration: UInt64 = 0,
        timestamp: MonotonicTimestamp,
        hands: [TrackedHandSnapshot],
        quality: TrackingQuality,
        diagnostics: TrackingDiagnostics = .zero,
        degradationReason: TrackingDegradationReason? = nil
    ) {
        self.captureGeneration = captureGeneration
        self.timestamp = timestamp
        self.hands = hands
        self.quality = quality
        self.diagnostics = diagnostics
        self.degradationReason = degradationReason
    }
}

public enum PoseKind: String, Codable, Equatable, Sendable {
    case openPalm, fist, pointer, scroll, pinch, unknown, lowConfidence
}

public enum ActiveGestureDiagnostic: String, Codable, Equatable, Sendable {
    case rest, pointer, pendingClick, scroll, zoom
}

public enum PointerSuppressionReason: String, Codable, Equatable, Sendable {
    case middleThumbPinchCandidate
    case pendingClick
    case scrolling
    case horizontalPinchZoom
    case multipleHands
    case trackingUnavailable
    case poseMismatch
}

public enum FistRejectionReason: String, Codable, Equatable, Sendable {
    case activePinchEpisode
    case middleThumbContactLikely
    case nonThumbNotCurled
    case insufficientConfidence
}

public struct GestureDiagnostics: Codable, Equatable, Sendable {
    public var recognizedPose: PoseKind?
    public var pendingClick: Bool
    public var activeGesture: ActiveGestureDiagnostic
    public var pinchDuration: TimeInterval?
    public var scrollDisplacement: Double?
    public var scrollDelta: Double?
    public var requiredJointConfidence: Double?
    public var degradationReason: TrackingDegradationReason?
    public var zoomDistance: Double?
    public var zoomDelta: Double?
    public var middleThumbNormalizedDistance: Double?
    public var pointerSuppressionReason: PointerSuppressionReason?
    public var scrollAnchor: Point2D?
    public var scrollVerticalDelta: Double?
    public var fistRejectionReason: FistRejectionReason?

    public init(
        recognizedPose: PoseKind? = nil,
        pendingClick: Bool = false,
        activeGesture: ActiveGestureDiagnostic = .rest,
        pinchDuration: TimeInterval? = nil,
        scrollDisplacement: Double? = nil,
        scrollDelta: Double? = nil,
        requiredJointConfidence: Double? = nil,
        degradationReason: TrackingDegradationReason? = nil,
        zoomDistance: Double? = nil,
        zoomDelta: Double? = nil,
        middleThumbNormalizedDistance: Double? = nil,
        pointerSuppressionReason: PointerSuppressionReason? = nil,
        scrollAnchor: Point2D? = nil,
        scrollVerticalDelta: Double? = nil,
        fistRejectionReason: FistRejectionReason? = nil
    ) {
        self.recognizedPose = recognizedPose
        self.pendingClick = pendingClick
        self.activeGesture = activeGesture
        self.pinchDuration = pinchDuration
        self.scrollDisplacement = scrollDisplacement
        self.scrollDelta = scrollDelta
        self.requiredJointConfidence = requiredJointConfidence
        self.degradationReason = degradationReason
        self.zoomDistance = zoomDistance
        self.zoomDelta = zoomDelta
        self.middleThumbNormalizedDistance = middleThumbNormalizedDistance
        self.pointerSuppressionReason = pointerSuppressionReason
        self.scrollAnchor = scrollAnchor
        self.scrollVerticalDelta = scrollVerticalDelta
        self.fistRejectionReason = fistRejectionReason
    }

    public static let safeDefault = Self()
}

public struct FingerMetrics: Codable, Equatable, Sendable {
    public var extensionScore: Double
    public var proximalAngleDegrees: Double
    public var distalAngleDegrees: Double
    public var reach: Double

    public init(
        extensionScore: Double,
        proximalAngleDegrees: Double,
        distalAngleDegrees: Double,
        reach: Double
    ) {
        self.extensionScore = extensionScore
        self.proximalAngleDegrees = proximalAngleDegrees
        self.distalAngleDegrees = distalAngleDegrees
        self.reach = reach
    }
}

public struct PoseMetrics: Codable, Equatable, Sendable {
    public var pose: PoseKind
    public var thumb: FingerMetrics
    public var index: FingerMetrics
    public var middle: FingerMetrics
    public var ring: FingerMetrics
    public var little: FingerMetrics
    public var pinchRatio: Double?
    public var indexMiddleTipSeparation: Double?
    public var palmWidth: Double
    public var minimumRequiredConfidence: Double

    public init(
        pose: PoseKind,
        thumb: FingerMetrics,
        index: FingerMetrics,
        middle: FingerMetrics,
        ring: FingerMetrics,
        little: FingerMetrics,
        pinchRatio: Double?,
        indexMiddleTipSeparation: Double? = nil,
        palmWidth: Double,
        minimumRequiredConfidence: Double
    ) {
        self.pose = pose
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.little = little
        self.pinchRatio = pinchRatio
        self.indexMiddleTipSeparation = indexMiddleTipSeparation
        self.palmWidth = palmWidth
        self.minimumRequiredConfidence = minimumRequiredConfidence
    }
}

public struct HandPoseSnapshot: Codable, Equatable, Sendable {
    public var handID: HandTrackID
    public var timestamp: MonotonicTimestamp
    public var metrics: PoseMetrics

    public init(handID: HandTrackID, timestamp: MonotonicTimestamp, metrics: PoseMetrics) {
        self.handID = handID
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

public enum ZoomEpisodePhase: String, Equatable, Sendable {
    case inactive
    case candidate
    case active
}

public struct ZoomEpisodeDiagnostic: Equatable, Sendable {
    public var phase: ZoomEpisodePhase
    public var handIDs: [HandTrackID]

    public init(phase: ZoomEpisodePhase, handIDs: [HandTrackID]) {
        self.phase = phase
        self.handIDs = handIDs.sorted()
    }

    public static let inactive = Self(phase: .inactive, handIDs: [])
}

public struct GestureFrameResult: Equatable, Sendable {
    public var poses: [HandPoseSnapshot]
    public var events: [GestureEvent]
    public var stateDescription: String
    public var zoomEpisode: ZoomEpisodeDiagnostic
    public var diagnostics: GestureDiagnostics

    public init(
        poses: [HandPoseSnapshot],
        events: [GestureEvent],
        stateDescription: String,
        zoomEpisode: ZoomEpisodeDiagnostic = .inactive,
        diagnostics: GestureDiagnostics = .safeDefault
    ) {
        self.poses = poses
        self.events = events
        self.stateDescription = stateDescription
        self.zoomEpisode = zoomEpisode
        self.diagnostics = diagnostics
    }
}
