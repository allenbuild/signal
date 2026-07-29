import XCTest
@testable import Signal

final class CommandGestureClassifierTests: XCTestCase {
    private let classifier = CommandGestureClassifier()

    func testCommandGestureContractContainsExactlyEightCasesAndNoFive() {
        XCTAssertEqual(
            CommandGesture.allCases,
            [
                .one, .two, .three, .four,
                .thumbsUp, .thumbsDown, .cShape, .fist
            ]
        )
        XCTAssertFalse(CommandGesture.allCases.map(\.rawValue).contains("five"))
    }

    func testRecognizesAllEightCommandPoses() {
        let samples: [(CommandGesture, TestPose)] = [
            (.one, .number([1, 0, 0, 0], thumb: 0.45)),
            (.two, .number([1, 1, 0, 0], thumb: 0.45)),
            (.three, .number([1, 1, 1, 0], thumb: 0.45)),
            (.four, .number([1, 1, 1, 1], thumb: 0)),
            (.thumbsUp, .thumb(up: true)),
            (.thumbsDown, .thumb(up: false)),
            (.cShape, .cShape),
            (.fist, .fist)
        ]

        for (gesture, pose) in samples {
            let sample = makeSample(pose)
            XCTAssertEqual(
                classifier.classify(
                    sample.hand,
                    poseMetrics: sample.metrics
                )?.gesture,
                gesture,
                "Expected \(gesture.rawValue)"
            )
        }
    }

    func testOpenFiveFingerPalmIsNotACommand() {
        let sample = makeSample(.number([1, 1, 1, 1], thumb: 1))
        XCTAssertNil(
            classifier.classify(sample.hand, poseMetrics: sample.metrics)
        )
    }

    func testIndexOnlyPoseRemainsACommandCandidateWithoutChangingControlMeaning() {
        let sample = makeSample(.number([1, 0, 0, 0], thumb: 0.45))
        let control = HandPoseClassifier().classify(sample.hand)

        XCTAssertEqual(control.pose, .pointer)
        XCTAssertEqual(
            classifier.classify(sample.hand, poseMetrics: sample.metrics)?.gesture,
            .one
        )
    }

    func testTranslationScaleAndHorizontalReflectionDoNotChangeRecognition() {
        for pose in [
            TestPose.number([1, 1, 1, 0], thumb: 0.45),
            .thumb(up: true),
            .thumb(up: false),
            .cShape,
            .fist
        ] {
            let baseline = makeSample(pose)
            let expected = classifier.classify(
                baseline.hand,
                poseMetrics: baseline.metrics
            )?.gesture
            XCTAssertNotNil(expected)

            for transform in [
                TestTransform(dx: 0.18, dy: -0.11, scale: 1, reflectX: false),
                TestTransform(dx: -0.07, dy: 0.06, scale: 1.35, reflectX: false),
                TestTransform(dx: 0, dy: 0, scale: 1, reflectX: true)
            ] {
                let changed = transformed(baseline, by: transform)
                XCTAssertEqual(
                    classifier.classify(
                        changed.hand,
                        poseMetrics: changed.metrics
                    )?.gesture,
                    expected
                )
            }
        }
    }

    func testActiveControlPinchSuppressesCommands() {
        let one = makeSample(.number([1, 0, 0, 0], thumb: 0.45))
        XCTAssertNil(
            classifier.classify(
                one.hand,
                poseMetrics: one.metrics,
                pinchActive: true
            )
        )
    }

    func testAmbiguousFingerStateAndUnsafeHandReturnNil() {
        var ambiguous = makeSample(.number([1, 0, 0, 0], thumb: 0.45))
        ambiguous.metrics.middle.extensionScore = 0.50
        XCTAssertNil(
            classifier.classify(
                ambiguous.hand,
                poseMetrics: ambiguous.metrics
            )
        )

        var uncertain = ambiguous.hand
        uncertain.associationCertain = false
        XCTAssertNil(
            classifier.classify(uncertain, poseMetrics: makeMetrics(
                thumb: 0.45,
                nonThumb: [1, 0, 0, 0]
            ))
        )

        var missing = makeSample(.fist).hand
        missing.missingDuration = 0.01
        XCTAssertNil(
            classifier.classify(missing, poseMetrics: makeSample(.fist).metrics)
        )
    }

    func testLowRequiredJointRejectsButIrrelevantFoldedTipDoesNot() {
        let sample = makeSample(.number([1, 0, 0, 0], thumb: 0.45))
        let weakIndex = replacingConfidence(
            0.10,
            for: .indexTip,
            in: sample
        )
        XCTAssertNil(
            classifier.classify(
                weakIndex.hand,
                poseMetrics: weakIndex.metrics
            )
        )

        let weakFoldedTip = replacingConfidence(
            0.10,
            for: .middleTip,
            in: sample
        )
        XCTAssertEqual(
            classifier.classify(
                weakFoldedTip.hand,
                poseMetrics: weakFoldedTip.metrics
            )?.gesture,
            .one
        )
    }

    func testCandidateConfidenceCannotHideWeakRequiredJoint() {
        let sample = replacingConfidence(
            0.63,
            for: .indexTip,
            in: makeSample(.number([1, 0, 0, 0], thumb: 0.45))
        )
        guard let candidate = classifier.classify(
            sample.hand,
            poseMetrics: sample.metrics
        ) else {
            return XCTFail("Expected a one-pose candidate")
        }
        XCTAssertEqual(candidate.requiredJointConfidence, 0.63, accuracy: 1e-12)
        XCTAssertEqual(candidate.confidence, 0.63, accuracy: 1e-12)
    }

    func testCAndThumbPosesDoNotCollapseIntoFist() {
        for (pose, expected) in [
            (TestPose.cShape, CommandGesture.cShape),
            (.thumb(up: true), .thumbsUp),
            (.thumb(up: false), .thumbsDown)
        ] {
            let sample = makeSample(pose)
            XCTAssertEqual(
                classifier.classify(
                    sample.hand,
                    poseMetrics: sample.metrics
                )?.gesture,
                expected
            )
        }
    }

    private func makeSample(_ pose: TestPose) -> TestSample {
        var points = canonicalPoints
        let metrics: PoseMetrics

        switch pose {
        case let .number(nonThumb, thumb):
            for (index, score) in nonThumb.enumerated() where score == 0 {
                foldFinger(index, in: &points)
            }
            metrics = makeMetrics(thumb: thumb, nonThumb: nonThumb)
        case let .thumb(up):
            foldNonThumbTips(in: &points)
            points[.thumbCMC] = Point2D(x: -0.08, y: 0.35)
            points[.thumbMP] = Point2D(x: -0.06, y: up ? 0.62 : 0.08)
            points[.thumbIP] = Point2D(x: -0.04, y: up ? 0.94 : -0.24)
            points[.thumbTip] = Point2D(x: -0.02, y: up ? 1.28 : -0.58)
            metrics = makeMetrics(thumb: 1, nonThumb: [0, 0, 0, 0])
        case .cShape:
            points[.thumbTip] = Point2D(x: -0.62, y: 1.03)
            points[.indexTip] = Point2D(x: -0.18, y: 1.18)
            points[.middleTip] = Point2D(x: 0.12, y: 1.25)
            points[.ringTip] = Point2D(x: 0.35, y: 1.16)
            points[.littleTip] = Point2D(x: 0.55, y: 1.02)
            metrics = makeMetrics(
                thumb: 0.45,
                nonThumb: [0.42, 0.44, 0.46, 0.43],
                angle: 118
            )
        case .fist:
            foldNonThumbTips(in: &points)
            points[.thumbTip] = Point2D(x: -0.34, y: 0.55)
            metrics = makeMetrics(thumb: 0.18, nonThumb: [0, 0, 0, 0])
        }

        return makeSample(points: points, metrics: metrics)
    }

    private func makeSample(
        points: [LandmarkName: Point2D],
        metrics: PoseMetrics,
        confidence: Double = 0.95,
        pointsAreNormalized: Bool = false
    ) -> TestSample {
        let normalizedPoints = pointsAreNormalized
            ? points
            : points.mapValues {
                Point2D(x: 0.50 + 0.14 * $0.x, y: 0.20 + 0.14 * $0.y)
            }
        var landmarks = HandLandmarks()
        for name in LandmarkName.allCases {
            if let point = normalizedPoints[name] {
                landmarks[name] = LandmarkSample(
                    position: point,
                    confidence: confidence
                )
            }
        }
        let palmWidth = tryUnwrap(normalizedPoints[.indexMCP]).distance(
            to: tryUnwrap(normalizedPoints[.littleMCP])
        )
        var adjustedMetrics = metrics
        adjustedMetrics.palmWidth = palmWidth
        let hand = TrackedHandSnapshot(
            id: HandTrackID(rawValue: 1),
            timestamp: MonotonicTimestamp(rawValue: 1),
            rawLandmarks: landmarks,
            filteredLandmarks: landmarks,
            palmWidth: palmWidth,
            palmScaleSource: .indexToLittleMCP,
            confidence: confidence,
            velocity: .zero,
            missingDuration: 0,
            associationCertain: true
        )
        return TestSample(hand: hand, metrics: adjustedMetrics)
    }

    private func makeMetrics(
        thumb: Double,
        nonThumb: [Double],
        angle: Double = 175
    ) -> PoseMetrics {
        precondition(nonThumb.count == 4)
        func finger(_ score: Double) -> FingerMetrics {
            FingerMetrics(
                extensionScore: score,
                proximalAngleDegrees: angle,
                distalAngleDegrees: angle,
                reach: score
            )
        }
        return PoseMetrics(
            pose: .unknown,
            thumb: finger(thumb),
            index: finger(nonThumb[0]),
            middle: finger(nonThumb[1]),
            ring: finger(nonThumb[2]),
            little: finger(nonThumb[3]),
            pinchRatio: nil,
            palmWidth: 1,
            minimumRequiredConfidence: 0.95
        )
    }

    private func transformed(
        _ sample: TestSample,
        by transform: TestTransform
    ) -> TestSample {
        var points: [LandmarkName: Point2D] = [:]
        for name in LandmarkName.allCases {
            guard let point = sample.hand.filteredLandmarks[name]?.position else {
                continue
            }
            let x = transform.reflectX ? -point.x : point.x
            points[name] = Point2D(
                x: x * transform.scale + transform.dx,
                y: point.y * transform.scale + transform.dy
            )
        }
        return makeSample(
            points: points,
            metrics: sample.metrics,
            confidence: sample.hand.confidence,
            pointsAreNormalized: true
        )
    }

    private func replacingConfidence(
        _ confidence: Double,
        for name: LandmarkName,
        in sample: TestSample
    ) -> TestSample {
        var result = sample
        result.hand.rawLandmarks[name]?.confidence = confidence
        return result
    }

    private func tryUnwrap<T>(
        _ value: T?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T {
        guard let value else {
            XCTFail("Expected non-nil fixture value", file: file, line: line)
            fatalError("Invalid deterministic test fixture")
        }
        return value
    }

    private func foldNonThumbTips(
        in points: inout [LandmarkName: Point2D]
    ) {
        for index in 0 ..< 4 {
            foldFinger(index, in: &points)
        }
    }

    private func foldFinger(
        _ index: Int,
        in points: inout [LandmarkName: Point2D]
    ) {
        switch index {
        case 0:
            points[.indexPIP] = Point2D(x: -0.48, y: 1.08)
            points[.indexDIP] = Point2D(x: -0.30, y: 0.93)
            points[.indexTip] = Point2D(x: -0.24, y: 0.64)
        case 1:
            points[.middlePIP] = Point2D(x: -0.10, y: 1.18)
            points[.middleDIP] = Point2D(x: 0.05, y: 1.02)
            points[.middleTip] = Point2D(x: -0.02, y: 0.68)
        case 2:
            points[.ringPIP] = Point2D(x: 0.24, y: 1.12)
            points[.ringDIP] = Point2D(x: 0.37, y: 0.96)
            points[.ringTip] = Point2D(x: 0.22, y: 0.65)
        case 3:
            points[.littlePIP] = Point2D(x: 0.53, y: 1.03)
            points[.littleDIP] = Point2D(x: 0.65, y: 0.88)
            points[.littleTip] = Point2D(x: 0.40, y: 0.61)
        default:
            XCTFail("Unexpected finger fixture index \(index)")
        }
    }

    private var canonicalPoints: [LandmarkName: Point2D] {
        [
            .wrist: Point2D(x: 0.00, y: 0.00),
            .thumbCMC: Point2D(x: -0.30, y: 0.25),
            .thumbMP: Point2D(x: -0.58, y: 0.43),
            .thumbIP: Point2D(x: -0.83, y: 0.57),
            .thumbTip: Point2D(x: -1.02, y: 0.70),
            .indexMCP: Point2D(x: -0.50, y: 0.80),
            .indexPIP: Point2D(x: -0.52, y: 1.27),
            .indexDIP: Point2D(x: -0.53, y: 1.59),
            .indexTip: Point2D(x: -0.54, y: 1.88),
            .middleMCP: Point2D(x: -0.12, y: 0.91),
            .middlePIP: Point2D(x: -0.12, y: 1.42),
            .middleDIP: Point2D(x: -0.12, y: 1.76),
            .middleTip: Point2D(x: -0.12, y: 2.04),
            .ringMCP: Point2D(x: 0.24, y: 0.84),
            .ringPIP: Point2D(x: 0.25, y: 1.30),
            .ringDIP: Point2D(x: 0.26, y: 1.61),
            .ringTip: Point2D(x: 0.27, y: 1.88),
            .littleMCP: Point2D(x: 0.52, y: 0.71),
            .littlePIP: Point2D(x: 0.56, y: 1.08),
            .littleDIP: Point2D(x: 0.59, y: 1.33),
            .littleTip: Point2D(x: 0.62, y: 1.55)
        ]
    }
}

private struct TestSample {
    var hand: TrackedHandSnapshot
    var metrics: PoseMetrics
}

private enum TestPose {
    case number([Double], thumb: Double)
    case thumb(up: Bool)
    case cShape
    case fist
}

private struct TestTransform {
    var dx: Double
    var dy: Double
    var scale: Double
    var reflectX: Bool
}
