import Foundation

public struct GestureTuning: Codable, Equatable, Sendable {
    /// Absolute safety ceiling for unreliable or missing tracking. This is a
    /// hard limit, not a user-adjustable recommendation.
    public static let maximumTrackingLossGraceDuration: TimeInterval = 0.150

    public var minimumLandmarkConfidence: Double
    public var poseEnterScore: Double
    public var poseExitScore: Double
    public var foldedMaximumScore: Double
    public var poseStabilityDuration: TimeInterval
    public var poseExitGraceDuration: TimeInterval
    public var pinchCloseRatio: Double
    public var pinchOpenRatio: Double
    public var pinchOpenRearmDuration: TimeInterval
    public var quickPinchMaximumDuration: TimeInterval
    public var doubleClickInterval: TimeInterval
    public var doubleClickSpatialTolerance: Double
    public var dragMinimumHoldDuration: TimeInterval
    public var dragActivationDisplacement: Double
    public var contextMaximumDisplacement: Double
    public var longPressDuration: TimeInterval
    public var pointerDeadZone: Double
    public var pointerSensitivity: Double
    public var pointerAcceleration: Double
    public var pointerMaximumDelta: Double
    public var scrollDeadZone: Double
    public var scrollSensitivityX: Double
    public var scrollSensitivityY: Double
    public var scrollAcceleration: Double
    public var scrollMaximumDelta: Double
    public var naturalScrolling: Bool
    public var scrollAxisLockRatio: Double
    public var zoomSensitivity: Double
    public var zoomDeadZoneFraction: Double
    public var zoomStepThreshold: Double
    public var zoomMaximumStepsPerFrame: Int
    public var trackingLossGraceDuration: TimeInterval
    public var associationPositionGate: Double
    public var associationScaleRatioMinimum: Double
    public var associationScaleRatioMaximum: Double
    public var associationAmbiguityMargin: Double
    public var trackRetentionDuration: TimeInterval
    public var filterResetGap: TimeInterval
    public var oneEuroMinimumCutoff: Double
    public var oneEuroDerivativeCutoff: Double
    public var oneEuroBeta: Double
    public var normalizedDiscontinuityStep: Double
    private var scrollStabilizationFramesStorage: Int? = 1
    private var pinchIntentRatioStorage: Double? = 0.46
    private var oneHandAxisMappingVersionStorage: Int? = 2

    /// Number of reliable frames used to settle the stable scroll anchor after
    /// a middle-thumb pinch closes. The optional backing keeps v1 settings
    /// decodable; a missing value reads as the new safe default.
    public var scrollStabilizationFrames: Int {
        get { scrollStabilizationFramesStorage ?? 2 }
        set { scrollStabilizationFramesStorage = newValue }
    }

    var hasStoredScrollStabilizationFrames: Bool {
        scrollStabilizationFramesStorage != nil
    }

    /// Outer contact-approach boundary. Pointer output clutches here, before
    /// the stricter close threshold owns a click/scroll/zoom episode.
    public var pinchIntentRatio: Double {
        get {
            pinchIntentRatioStorage
                ?? max(pinchOpenRatio, min(1, pinchOpenRatio + 0.08))
        }
        set { pinchIntentRatioStorage = newValue }
    }

    var needsOneHandAxisMappingMigration: Bool {
        oneHandAxisMappingVersionStorage != 2
    }

    mutating func applyMiddleThumbDefaultsMigration() {
        scrollStabilizationFramesStorage = 2
        if pointerSensitivity == 600 {
            pointerSensitivity = 400
        }
    }

    mutating func applyOneHandAxisMappingMigration() {
        let storedVersion = oneHandAxisMappingVersionStorage ?? 0

        if storedVersion < 1 {
            pinchIntentRatioStorage = max(pinchOpenRatio, min(1, pinchOpenRatio + 0.08))

            // Only exact former defaults migrate. User-tuned values remain intact.
            if pinchCloseRatio == 0.22, pinchOpenRatio == 0.32 {
                pinchCloseRatio = 0.28
                pinchOpenRatio = 0.38
                pinchIntentRatioStorage = 0.46
            }
            if quickPinchMaximumDuration == 0.300 {
                quickPinchMaximumDuration = 0.400
            }
            if pinchScrollActivationDisplacement == 0.06 {
                pinchScrollActivationDisplacement = 0.08
            }
            if zoomSensitivity == 1 {
                zoomSensitivity = 2
            }
        }

        if storedVersion < 2 {
            // Version 1 required too much movement and produced sub-pixel
            // scroll deltas. Lift its entire formerly exposed low range to a
            // useful floor; values already tuned above that range are kept.
            if scrollStabilizationFrames == 2 {
                scrollStabilizationFrames = 1
            }
            if pinchScrollActivationDisplacement == 0.08 {
                pinchScrollActivationDisplacement = 0.04
            }
            if scrollAxisLockRatio == 1.25 {
                scrollAxisLockRatio = 1.15
            }
            if scrollSensitivityY <= 80 {
                scrollSensitivityY = 120
            }
            if zoomStepThreshold == 0.08 {
                zoomStepThreshold = 0.06
            }
        }

        oneHandAxisMappingVersionStorage = 2
    }

    /// Migration aliases: the stored drag fields now tune pinch-scroll entry.
    public var pinchScrollActivationDisplacement: Double {
        get { dragActivationDisplacement }
        set { dragActivationDisplacement = newValue }
    }

    public var pinchMotionActivationDisplacement: Double {
        get { dragActivationDisplacement }
        set { dragActivationDisplacement = newValue }
    }

    public var pinchScrollHoldDuration: TimeInterval {
        get { dragMinimumHoldDuration }
        set { dragMinimumHoldDuration = newValue }
    }

    public static let safeDefaults = Self(
        minimumLandmarkConfidence: 0.60,
        poseEnterScore: 0.75,
        poseExitScore: 0.55,
        foldedMaximumScore: 0.35,
        poseStabilityDuration: 0.140,
        poseExitGraceDuration: 0.080,
        pinchCloseRatio: 0.28,
        pinchOpenRatio: 0.38,
        pinchOpenRearmDuration: 0.070,
        quickPinchMaximumDuration: 0.400,
        doubleClickInterval: 0.340,
        doubleClickSpatialTolerance: 0.35,
        dragMinimumHoldDuration: 0.180,
        dragActivationDisplacement: 0.04,
        contextMaximumDisplacement: 0.06,
        longPressDuration: 0.650,
        pointerDeadZone: 0.012,
        pointerSensitivity: 400,
        pointerAcceleration: 0.35,
        pointerMaximumDelta: 80,
        scrollDeadZone: 0.020,
        scrollSensitivityX: 35,
        scrollSensitivityY: 120,
        scrollAcceleration: 0.25,
        scrollMaximumDelta: 80,
        naturalScrolling: true,
        scrollAxisLockRatio: 1.15,
        zoomSensitivity: 2,
        zoomDeadZoneFraction: 0.02,
        zoomStepThreshold: 0.06,
        zoomMaximumStepsPerFrame: 2,
        trackingLossGraceDuration: 0.150,
        associationPositionGate: 1.25,
        associationScaleRatioMinimum: 0.55,
        associationScaleRatioMaximum: 1.80,
        associationAmbiguityMargin: 0.15,
        trackRetentionDuration: 0.350,
        filterResetGap: 0.200,
        oneEuroMinimumCutoff: 1.7,
        oneEuroDerivativeCutoff: 1.0,
        oneEuroBeta: 0.35,
        normalizedDiscontinuityStep: 0.35
    )

    public func validated() -> Self {
        isValid ? self : .safeDefaults
    }

    private var isValid: Bool {
        let finiteValues = [
            minimumLandmarkConfidence,
            poseEnterScore,
            poseExitScore,
            foldedMaximumScore,
            poseStabilityDuration,
            poseExitGraceDuration,
            pinchCloseRatio,
            pinchOpenRatio,
            pinchOpenRearmDuration,
            quickPinchMaximumDuration,
            doubleClickInterval,
            doubleClickSpatialTolerance,
            dragMinimumHoldDuration,
            dragActivationDisplacement,
            contextMaximumDisplacement,
            longPressDuration,
            pointerDeadZone,
            pointerSensitivity,
            pointerAcceleration,
            pointerMaximumDelta,
            scrollDeadZone,
            scrollSensitivityX,
            scrollSensitivityY,
            scrollAcceleration,
            scrollMaximumDelta,
            scrollAxisLockRatio,
            zoomSensitivity,
            zoomDeadZoneFraction,
            zoomStepThreshold,
            trackingLossGraceDuration,
            associationPositionGate,
            associationScaleRatioMinimum,
            associationScaleRatioMaximum,
            associationAmbiguityMargin,
            trackRetentionDuration,
            filterResetGap,
            oneEuroMinimumCutoff,
            oneEuroDerivativeCutoff,
            oneEuroBeta,
            normalizedDiscontinuityStep
        ]
        guard finiteValues.allSatisfy(\.isFinite) else { return false }

        let unitScores = [
            minimumLandmarkConfidence,
            poseEnterScore,
            poseExitScore,
            foldedMaximumScore
        ]
        guard unitScores.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return false }
        guard poseEnterScore > poseExitScore, poseExitScore > foldedMaximumScore else { return false }
        guard poseStabilityDuration >= 0, poseExitGraceDuration >= 0 else { return false }
        guard pinchCloseRatio >= 0, pinchCloseRatio < pinchOpenRatio,
              pinchOpenRatio <= pinchIntentRatio, pinchIntentRatio <= 1 else { return false }
        guard pinchOpenRearmDuration >= 0 else { return false }
        guard quickPinchMaximumDuration >= 0 else { return false }
        guard doubleClickInterval > 0, doubleClickSpatialTolerance >= 0 else { return false }
        guard pinchScrollHoldDuration >= 0,
              pinchScrollActivationDisplacement > 0,
              (0 ... 6).contains(scrollStabilizationFrames) else { return false }
        guard contextMaximumDisplacement >= 0 else { return false }
        guard longPressDuration > 0 else { return false }
        guard pointerDeadZone >= 0, pointerSensitivity > 0,
              pointerAcceleration >= 0, pointerMaximumDelta > 0 else { return false }
        guard scrollDeadZone >= 0, scrollSensitivityX > 0, scrollSensitivityY > 0,
              scrollAcceleration >= 0, scrollMaximumDelta > 0,
              scrollAxisLockRatio > 1 else { return false }
        guard zoomSensitivity > 0, zoomDeadZoneFraction >= 0,
              zoomStepThreshold > 0,
              (1 ... 8).contains(zoomMaximumStepsPerFrame) else { return false }
        guard trackingLossGraceDuration >= 0,
              trackingLossGraceDuration <= Self.maximumTrackingLossGraceDuration else { return false }
        guard associationPositionGate > 0,
              associationScaleRatioMinimum > 0,
              associationScaleRatioMinimum < associationScaleRatioMaximum,
              associationAmbiguityMargin >= 0 else { return false }
        guard trackRetentionDuration >= 0, filterResetGap >= 0 else { return false }
        guard oneEuroMinimumCutoff > 0, oneEuroDerivativeCutoff > 0,
              oneEuroBeta >= 0, normalizedDiscontinuityStep > 0 else { return false }
        return true
    }
}
