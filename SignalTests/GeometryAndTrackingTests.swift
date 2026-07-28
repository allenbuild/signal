import XCTest
@testable import Signal

final class GeometryAndTrackingTests: XCTestCase {
#if !TRACKING_PARTITION
    private let classifier = HandPoseClassifier()

    func testCanonicalPalmWidthAndPoseFixtures() {
        let cases: [(FixturePose, PoseKind)] = [
            (.openPalm, .openPalm),
            (.fist, .fist),
            (.pointer, .pointer),
            (.scroll, .unknown),
            (.pinch(ratio: 0.20), .pinch)
        ]

        for (index, fixture) in cases.enumerated() {
            let hand = SyntheticHand.pose(fixture.0).tracked(id: UInt64(index + 1), at: 0)
            let metrics = classifier.classify(hand)
            XCTAssertEqual(metrics.pose, fixture.1, "Unexpected pose for fixture \(fixture.0)")
            XCTAssertEqual(metrics.palmWidth, 0.14, accuracy: 1e-12)
            XCTAssertTrue(metrics.index.extensionScore.isFinite)
            XCTAssertTrue(metrics.middle.extensionScore.isFinite)
        }
    }

    func testFingerGeometryIsInvariantForMirroredHands() {
        let right = SyntheticHand.pose(.pointer).withChirality(.right).tracked(id: 1, at: 0)
        let left = SyntheticHand.pose(.pointer)
            .withChirality(.right)
            .reflectedAboutPreviewMidline()
            .tracked(id: 2, at: 0)

        let rightMetrics = classifier.classify(right)
        let leftMetrics = classifier.classify(left)

        XCTAssertEqual(rightMetrics.pose, .pointer)
        XCTAssertEqual(leftMetrics.pose, .pointer)
        XCTAssertEqual(rightMetrics.index.extensionScore, leftMetrics.index.extensionScore, accuracy: 1e-9)
        XCTAssertEqual(rightMetrics.middle.extensionScore, leftMetrics.middle.extensionScore, accuracy: 1e-9)
        XCTAssertEqual(rightMetrics.palmWidth, leftMetrics.palmWidth, accuracy: 1e-12)
    }

    func testPoseIsInvariantToTranslationScaleRotationAndReflection() {
        let base = SyntheticHand.pose(.scroll)
        let transformed = base
            .translatedLocal(dx: 0.20, dy: -0.10)
            .scaledLocal(1.5)
            .rotatedLocal(.pi / 6)
            .reflectedAboutPreviewMidline()

        let originalMetrics = classifier.classify(base.tracked(id: 1, at: 0))
        let transformedMetrics = classifier.classify(transformed.tracked(id: 2, at: 0))

        XCTAssertEqual(originalMetrics.pose, .unknown)
        XCTAssertEqual(transformedMetrics.pose, .unknown)
        XCTAssertEqual(originalMetrics.index.extensionScore, transformedMetrics.index.extensionScore, accuracy: 1e-9)
        XCTAssertEqual(originalMetrics.middle.extensionScore, transformedMetrics.middle.extensionScore, accuracy: 1e-9)
    }

    func testPinchRatioAndConfidenceBoundaries() {
        let closed = classifier.classify(SyntheticHand.pose(.pinch(ratio: 0.22)).tracked(at: 0))
        let open = classifier.classify(SyntheticHand.pose(.pinch(ratio: 0.32)).tracked(at: 0))
        XCTAssertEqual(closed.pinchRatio ?? -1, 0.22, accuracy: 1e-12)
        XCTAssertEqual(open.pinchRatio ?? -1, 0.32, accuracy: 1e-12)

        let rejected = SyntheticHand.pose(.pointer)
            .withConfidence(0.599, for: .indexTip)
            .tracked(at: 0)
        let accepted = SyntheticHand.pose(.pointer)
            .withConfidence(0.600, for: .indexTip)
            .tracked(at: 0)
        XCTAssertEqual(classifier.classify(rejected).pose, .unknown)
        XCTAssertEqual(classifier.classify(accepted).pose, .pointer)
    }

    func testMissingOrNonfiniteGestureLandmarksAreSafeNeutral() {
        let missing = SyntheticHand.pose(.pointer).without(.indexTip).tracked(at: 0)
        XCTAssertEqual(classifier.classify(missing).pose, .unknown)

        var nonfinite = SyntheticHand.pose(.pointer).landmarks()
        nonfinite[.indexTip] = LandmarkSample(position: Point2D(x: .nan, y: 0.4), confidence: 0.95)
        let hand = TrackedHandSnapshot(
            id: HandTrackID(rawValue: 1),
            timestamp: MonotonicTimestamp(rawValue: 0),
            rawLandmarks: nonfinite,
            filteredLandmarks: nonfinite,
            palmWidth: 0.14,
            palmScaleSource: .indexToLittleMCP,
            confidence: 0.95,
            velocity: Point2D(x: 0, y: 0),
            missingDuration: 0,
            associationCertain: true
        )
        XCTAssertEqual(classifier.classify(hand).pose, .unknown)
    }
#endif

#if !GEOMETRY_PARTITION
    func testVisionBoundaryAcceptsMiddleMCPFallbackAndReportsPalmFailures() {
        let fallbackPoints: [LandmarkName: VisionLandmarkPoint] = [
            .wrist: .init(x: 0.50, y: 0.20, confidence: 0.95),
            .middleMCP: .init(x: 0.50, y: 0.70, confidence: 0.90)
        ]
        let fallback = VisionLandmarkBoundary.mapWithReason(
            fallbackPoints,
            timestamp: .init(rawValue: 1),
            chirality: .right,
            minimumConfidence: 0.60
        )
        let observation = try? XCTUnwrap(fallback.observation)
        XCTAssertNil(fallback.rejectionReason)
        let geometry = observation.flatMap {
            PalmGeometryEstimator.estimate(
                landmarks: $0.landmarks,
                minimumConfidence: 0.60
            )
        }
        XCTAssertEqual(geometry?.scaleSource, .wristToMiddleMCP)

        let collapsedPrimaryWithFallback = VisionLandmarkBoundary.mapWithReason(
            [
                .wrist: .init(x: 0.50, y: 0.20, confidence: 0.95),
                .indexMCP: .init(x: 0.40, y: 0.60, confidence: 0.95),
                .littleMCP: .init(x: 0.40, y: 0.60, confidence: 0.95),
                .middleMCP: .init(x: 0.50, y: 0.60, confidence: 0.95)
            ],
            timestamp: .init(rawValue: 1.5),
            chirality: .right,
            minimumConfidence: 0.60
        )
        let fallbackAfterInvalidPrimary = try? XCTUnwrap(
            collapsedPrimaryWithFallback.observation
        )
        XCTAssertNil(collapsedPrimaryWithFallback.rejectionReason)
        let recoveredGeometry = fallbackAfterInvalidPrimary.flatMap {
            PalmGeometryEstimator.estimate(
                landmarks: $0.landmarks,
                minimumConfidence: 0.60
            )
        }
        XCTAssertEqual(recoveredGeometry?.scaleSource, .wristToMiddleMCP)

        let anchorsMissing = VisionLandmarkBoundary.mapWithReason(
            [.wrist: .init(x: 0.50, y: 0.20, confidence: 0.95)],
            timestamp: .init(rawValue: 2),
            chirality: .unknown,
            minimumConfidence: 0.60
        )
        XCTAssertNil(anchorsMissing.observation)
        XCTAssertEqual(anchorsMissing.rejectionReason, .palmAnchorsMissing)

        let invalidScale = VisionLandmarkBoundary.mapWithReason(
            [
                .wrist: .init(x: 0.50, y: 0.20, confidence: 0.95),
                .middleMCP: .init(x: 0.50, y: 0.20, confidence: 0.95)
            ],
            timestamp: .init(rawValue: 3),
            chirality: .unknown,
            minimumConfidence: 0.60
        )
        XCTAssertNil(invalidScale.observation)
        XCTAssertEqual(invalidScale.rejectionReason, .invalidPalmScale)
    }

    func testTrackingServiceKeepsAcceptedHandGoodWhenSecondObservationIsRejected() {
        let service = TrackingService()
        let accepted = SyntheticHand.pose(.pointer).rawObservation(at: 10)
        let snapshot = service.process(
            rawObservations: [accepted],
            rejectionReasons: [.palmAnchorsMissing],
            timestamp: .init(rawValue: 10),
            generation: 1
        )

        XCTAssertEqual(snapshot?.quality, .good)
        XCTAssertNil(snapshot?.degradationReason)
        XCTAssertEqual(snapshot?.hands.count, 1)
        XCTAssertTrue(snapshot?.hands.first?.associationCertain == true)
    }

    func testTrackingServiceRejectsEndToEndStaleFrameBeforeAssociationAndOutput() throws {
        let clock = GeometryTrackingClock(100.050)
        let service = TrackingService(
            tuning: .safeDefaults,
            currentUptime: { clock.value }
        )
        let engine = GestureEngine(tuning: .safeDefaults)
        let pointer = SyntheticHand.pose(.pointer)

        let first = try XCTUnwrap(service.process(
            rawObservations: [pointer.rawObservation(at: 100.000)],
            rejectionReasons: [],
            timestamp: .init(rawValue: 100.000),
            generation: 1,
            enforceFrameAge: true
        ))
        XCTAssertEqual(first.quality, .good)
        XCTAssertEqual(engine.process(first).events, [])

        clock.value = 100.150
        let established = try XCTUnwrap(service.process(
            rawObservations: [pointer.rawObservation(at: 100.140)],
            rejectionReasons: [],
            timestamp: .init(rawValue: 100.140),
            generation: 1,
            enforceFrameAge: true
        ))
        XCTAssertEqual(established.quality, .good)
        XCTAssertEqual(engine.process(established).events, [])
        let establishedIndex = try XCTUnwrap(
            established.hands.first?.rawLandmarks[.indexTip]?.position
        )

        clock.value = 100.311
        let moved = pointer.translatedLocal(dx: 0.04, dy: 0)
        let stale = try XCTUnwrap(service.process(
            rawObservations: [moved.rawObservation(at: 100.160)],
            rejectionReasons: [],
            timestamp: .init(rawValue: 100.160),
            generation: 1,
            enforceFrameAge: true
        ))

        XCTAssertEqual(stale.quality, .degraded)
        XCTAssertEqual(stale.degradationReason, .staleFrame)
        XCTAssertEqual(stale.diagnostics.endToEndLatencyMilliseconds, 151, accuracy: 1e-6)
        XCTAssertEqual(stale.diagnostics.droppedFrames, 1)
        XCTAssertEqual(stale.hands.first?.rawLandmarks[.indexTip]?.position, establishedIndex)
        XCTAssertTrue(stale.hands.allSatisfy { !$0.associationCertain })

        let staleGesture = engine.process(stale)
        XCTAssertEqual(staleGesture.events, [])
        XCTAssertEqual(staleGesture.diagnostics.degradationReason, .staleFrame)
        XCTAssertEqual(engine.advance(to: .init(rawValue: 100.3099)), [])
        XCTAssertEqual(
            engine.advance(to: .init(rawValue: 100.3100)),
            [.trackingLost]
        )
    }

    func testNonPalmFilterReacquisitionAndOccludedFistTipsRemainTrackingGood() {
        var associator = HandAssociator(tuning: .safeDefaults)
        let initial = associator.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 20)],
            at: .init(rawValue: 20)
        )
        let initialID = initial.hands.first?.id

        let thumbOccluded = SyntheticHand.pose(.pointer)
            .withConfidence(0.30, for: .thumbTip)
            .rawObservation(at: 20.050)
        let occluded = associator.process(
            observations: [thumbOccluded],
            at: .init(rawValue: 20.050)
        )
        XCTAssertEqual(occluded.quality, .good)
        XCTAssertNil(occluded.degradationReason)

        // Reappearing after the per-joint reset gap resets only thumbTip's
        // filter. It must not invalidate the already-matched palm identity.
        let recovered = associator.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 20.160)],
            at: .init(rawValue: 20.160)
        )
        XCTAssertEqual(recovered.quality, .good)
        XCTAssertNil(recovered.degradationReason)
        XCTAssertEqual(recovered.hands.first?.id, initialID)
        XCTAssertTrue(recovered.hands.first?.associationCertain == true)

        let fistWithOccludedTips = [
            LandmarkName.indexTip, .middleTip, .ringTip, .littleTip
        ].reduce(SyntheticHand.pose(.fist)) { hand, landmark in
            hand.withConfidence(0.30, for: landmark)
        }
        let fist = associator.process(
            observations: [fistWithOccludedTips.rawObservation(at: 20.190)],
            at: .init(rawValue: 20.190)
        )
        XCTAssertEqual(fist.quality, .good)
        XCTAssertNil(fist.degradationReason)
        XCTAssertEqual(fist.hands.first?.id, initialID)
        XCTAssertTrue(fist.hands.first?.associationCertain == true)
    }

    func testRetainedMissingSecondHandDoesNotPoisonCurrentCertainHand() {
        var associator = HandAssociator(tuning: .safeDefaults)
        let left = SyntheticHand.pose(.pointer).translatedLocal(dx: -1.20, dy: 0)
        let right = SyntheticHand.pose(.pointer).translatedLocal(dx: 1.20, dy: 0)
        _ = associator.process(
            observations: [left.rawObservation(at: 30), right.rawObservation(at: 30)],
            at: .init(rawValue: 30)
        )

        let update = associator.process(
            observations: [left.translatedLocal(dx: 0.05, dy: 0).rawObservation(at: 30.033)],
            at: .init(rawValue: 30.033)
        )

        XCTAssertEqual(update.hands.count, 2)
        XCTAssertEqual(update.hands.filter { $0.missingDuration == 0 }.count, 1)
        XCTAssertEqual(update.quality, .good)
        XCTAssertNil(update.degradationReason)
    }

    func testAssociationReportsGenuineNoHandIdentityLossAndAmbiguityReasons() {
        var missing = HandAssociator(tuning: .safeDefaults)
        let empty = missing.process(observations: [], at: .init(rawValue: 40))
        XCTAssertEqual(empty.quality, .absent)
        XCTAssertEqual(empty.degradationReason, .noHandDetected)

        _ = missing.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 40.010)],
            at: .init(rawValue: 40.010)
        )
        let identityLost = missing.process(observations: [], at: .init(rawValue: 40.050))
        XCTAssertEqual(identityLost.quality, .degraded)
        XCTAssertEqual(identityLost.degradationReason, .handIdentityLost)

        var ambiguous = HandAssociator(tuning: .safeDefaults)
        _ = ambiguous.process(
            observations: [
                SyntheticHand.pose(.pointer).translatedLocal(dx: -0.40, dy: 0).rawObservation(at: 50),
                SyntheticHand.pose(.pointer).translatedLocal(dx: 0.40, dy: 0).rawObservation(at: 50)
            ],
            at: .init(rawValue: 50)
        )
        let same = SyntheticHand.pose(.pointer).rawObservation(at: 50.033)
        let ambiguousUpdate = ambiguous.process(
            observations: [same, same],
            at: .init(rawValue: 50.033)
        )
        XCTAssertEqual(ambiguousUpdate.quality, .degraded)
        XCTAssertEqual(ambiguousUpdate.degradationReason, .associationAmbiguous)
    }

    func testAssociationKeepsStableIDsWhenObservationOrderSwaps() {
        var associator = HandAssociator(tuning: .safeDefaults)
        let left0 = SyntheticHand.pose(.pointer).translatedLocal(dx: -1.20, dy: 0).rawObservation(at: 10.000)
        let right0 = SyntheticHand.pose(.pointer).translatedLocal(dx: 1.20, dy: 0).rawObservation(at: 10.000)
        let first = associator.process(
            observations: [right0, left0],
            at: MonotonicTimestamp(rawValue: 10.000)
        )

        XCTAssertEqual(first.hands.count, 2)
        let firstBySide = Dictionary(uniqueKeysWithValues: first.hands.map {
            (($0.rawLandmarks[.wrist]?.position.x ?? 0) < 0.5 ? "left" : "right", $0.id)
        })

        let left1 = SyntheticHand.pose(.pointer).translatedLocal(dx: -1.10, dy: 0).rawObservation(at: 10.033)
        let right1 = SyntheticHand.pose(.pointer).translatedLocal(dx: 1.10, dy: 0).rawObservation(at: 10.033)
        let second = associator.process(
            observations: [left1, right1],
            at: MonotonicTimestamp(rawValue: 10.033)
        )
        let secondBySide = Dictionary(uniqueKeysWithValues: second.hands.map {
            (($0.rawLandmarks[.wrist]?.position.x ?? 0) < 0.5 ? "left" : "right", $0.id)
        })

        XCTAssertEqual(secondBySide["left"], firstBySide["left"])
        XCTAssertEqual(secondBySide["right"], firstBySide["right"])
        XCTAssertTrue(second.hands.allSatisfy(\.associationCertain))
    }

    func testLandmarkFilterResetsAfterExtendedGap() {
        var bank = LandmarkFilterBank()
        var tuning = GestureTuning.safeDefaults
        tuning.oneEuroMinimumCutoff = 1
        tuning.oneEuroDerivativeCutoff = 1
        tuning.oneEuroBeta = 0

        let first = SyntheticHand.pose(.pointer).landmarks()
        _ = bank.filter(
            first,
            at: MonotonicTimestamp(rawValue: 1.000),
            palmWidth: 0.14,
            tuning: tuning,
            forceReset: true
        )

        let moved = SyntheticHand.pose(.pointer).translatedLocal(dx: 0.02, dy: 0).landmarks()
        let continuous = bank.filter(
            moved,
            at: MonotonicTimestamp(rawValue: 1.050),
            palmWidth: 0.14,
            tuning: tuning,
            forceReset: false
        )
        XCTAssertFalse(continuous.resetOccurred)

        let afterGapRaw = SyntheticHand.pose(.pointer).translatedLocal(dx: 0.04, dy: 0).landmarks()
        let afterGap = bank.filter(
            afterGapRaw,
            at: MonotonicTimestamp(rawValue: 1.151),
            palmWidth: 0.14,
            tuning: tuning,
            forceReset: false
        )
        XCTAssertTrue(afterGap.resetOccurred)
        XCTAssertEqual(afterGap.landmarks[.wrist]?.position, afterGapRaw[.wrist]?.position)
    }
#endif
}

private final class GeometryTrackingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double

    init(_ value: Double) {
        storedValue = value
    }

    var value: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
