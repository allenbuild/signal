import XCTest
@testable import SignalCore

final class GestureActivationTests: XCTestCase {
    private let classifier = CommandGestureClassifier()

    func testOneThroughFiveAndFistFixtures() {
        XCTAssertEqual(classify([0, 1, 0, 0, 0]), .one)
        XCTAssertEqual(classify([0, 1, 1, 0, 0]), .two)
        XCTAssertEqual(classify([0, 1, 1, 1, 0]), .three)
        XCTAssertEqual(classify([0, 1, 1, 1, 1]), .four)
        XCTAssertEqual(classify([1, 1, 1, 1, 1]), .five)
        XCTAssertEqual(classify([0, 0, 0, 0, 0]), .fist)
    }

    func testThumbsUpAndDownAreHandednessInvariant() {
        for handedness in Handedness.allCases {
            XCTAssertEqual(classify([1, 0, 0, 0, 0], handedness: handedness, thumbVertical: 1), .thumbsUp)
            XCTAssertEqual(classify([1, 0, 0, 0, 0], handedness: handedness, thumbVertical: -1), .thumbsDown)
        }
    }

    func testCShapeUsesCurvatureAndGapNotFingerCountAlone() {
        let positive = features(
            [0.45, 0.5, 0.5, 0.5, 0.5],
            gap: 0.72,
            curvature: 1
        )
        XCTAssertEqual(classifier.classify(positive)?.gesture, .cShape)

        let badGap = features(
            [0.45, 0.5, 0.5, 0.5, 0.5],
            gap: 2.5,
            curvature: 0
        )
        XCTAssertNotEqual(classifier.classify(badGap)?.gesture, .cShape)
    }

    func testLowRequiredJointConfidenceRejectsGesture() {
        var sample = features([0, 1, 0, 0, 0])
        sample.requiredConfidence = 0.2
        XCTAssertNil(classifier.classify(sample))
    }

    func testNormalizedPalmGeometryRecognizesPointerPose() {
        let sample = HandLandmarks(handedness: .right, joints: [
            .wrist: .init(.init(x: 0, y: 0)),
            .thumbCMC: .init(.init(x: -0.25, y: 0.18)),
            .thumbMP: .init(.init(x: -0.18, y: 0.25)),
            .thumbIP: .init(.init(x: -0.10, y: 0.18)),
            .thumbTip: .init(.init(x: -0.02, y: 0.12)),
            .indexMCP: .init(.init(x: -0.22, y: 0.32)),
            .indexPIP: .init(.init(x: -0.22, y: 0.58)),
            .indexDIP: .init(.init(x: -0.22, y: 0.82)),
            .indexTip: .init(.init(x: -0.22, y: 1.05)),
            .middleMCP: .init(.init(x: 0, y: 0.35)),
            .middlePIP: .init(.init(x: 0, y: 0.55)),
            .middleDIP: .init(.init(x: 0.12, y: 0.43)),
            .middleTip: .init(.init(x: 0.08, y: 0.29)),
            .ringMCP: .init(.init(x: 0.20, y: 0.32)),
            .ringPIP: .init(.init(x: 0.20, y: 0.51)),
            .ringDIP: .init(.init(x: 0.31, y: 0.40)),
            .ringTip: .init(.init(x: 0.27, y: 0.27)),
            .littleMCP: .init(.init(x: 0.38, y: 0.27)),
            .littlePIP: .init(.init(x: 0.38, y: 0.43)),
            .littleDIP: .init(.init(x: 0.47, y: 0.34)),
            .littleTip: .init(.init(x: 0.43, y: 0.23))
        ])
        XCTAssertEqual(classifier.classify(sample)?.gesture, .one)
    }

    func testStableHoldTriggersOnceThenRequiresRelease() {
        var engine = CommandActivationEngine()
        let context = CommandContext(mode: .command)
        XCTAssertEqual(
            engine.update(candidate: .init(.five, confidence: 0.9), at: 0, context: context),
            .progressing(gesture: .five, progress: 0, confidence: 0.9)
        )
        XCTAssertEqual(
            engine.update(candidate: .init(.five, confidence: 0.9), at: 0.6, context: context),
            .triggered(.five)
        )
        XCTAssertEqual(
            engine.update(candidate: .init(.five, confidence: 0.9), at: 0.7, context: context),
            .releaseRequired(.five)
        )
    }

    func testConfidenceGapGraceAndReleaseGate() {
        var engine = CommandActivationEngine()
        let context = CommandContext(mode: .command)
        _ = engine.update(candidate: .init(.two, confidence: 0.9), at: 0, context: context)
        let grace = engine.update(candidate: nil, at: 0.05, context: context)
        guard case .progressing(let gesture, _, _) = grace else { return XCTFail("Expected grace") }
        XCTAssertEqual(gesture, .two)
        XCTAssertEqual(engine.update(candidate: nil, at: 0.3, context: context), .idle)
    }

    func testModeGatesAndHybridOneBehavior() {
        XCTAssertFalse(CommandContext(mode: .touch).permits(.five))
        XCTAssertTrue(CommandContext(mode: .command).permits(.one))
        XCTAssertTrue(CommandContext(mode: .hybrid).permits(.two))
        XCTAssertFalse(CommandContext(mode: .hybrid).permits(.one))
        XCTAssertTrue(CommandContext(
            mode: .hybrid,
            oneCommandEnabledInHybrid: true,
            onePoseStationaryDuration: 0.9
        ).permits(.one))
        XCTAssertFalse(CommandContext(mode: .command, pinchActive: true).permits(.five))
        XCTAssertFalse(CommandContext(mode: .command, recording: true).permits(.five))
        XCTAssertFalse(CommandContext(mode: .command, outputPaused: true).permits(.five))
    }

    func testCooldownPreventsEarlyRetriggerAfterRelease() {
        var engine = CommandActivationEngine()
        let context = CommandContext(mode: .command)
        _ = engine.update(candidate: .init(.fist, confidence: 1), at: 0, context: context)
        XCTAssertEqual(engine.update(candidate: .init(.fist, confidence: 1), at: 0.6, context: context), .triggered(.fist))
        _ = engine.update(candidate: nil, at: 0.8, context: context)
        _ = engine.update(candidate: nil, at: 1.0, context: context)
        _ = engine.update(candidate: .init(.fist, confidence: 1), at: 1.05, context: context)
        let early = engine.update(candidate: .init(.fist, confidence: 1), at: 1.4, context: context)
        guard case .progressing = early else { return XCTFail("Cooldown should suppress trigger") }
    }

    private func classify(
        _ values: [Double],
        handedness: Handedness = .right,
        thumbVertical: Double = 0
    ) -> CommandGesture? {
        classifier.classify(features(values, handedness: handedness, thumbVertical: thumbVertical))?.gesture
    }

    private func features(
        _ values: [Double],
        handedness: Handedness = .right,
        thumbVertical: Double = 0,
        gap: Double = 0.72,
        curvature: Double = 0
    ) -> GestureFeatures {
        let fingers = Finger.allCases
        let map = Dictionary(uniqueKeysWithValues: zip(fingers, values))
        return GestureFeatures(
            handedness: handedness,
            fingerExtension: map,
            jointStraightness: map,
            thumbVertical: thumbVertical,
            thumbFingerGap: gap,
            cCurvature: curvature,
            palmFacing: 1,
            requiredConfidence: 1
        )
    }
}
