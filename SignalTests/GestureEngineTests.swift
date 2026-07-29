import Foundation
import XCTest
@testable import Signal

final class GestureEngineTests: XCTestCase {
    func testProductionPointerSensitivityIsRetunedTo400() {
        XCTAssertEqual(GestureTuning.safeDefaults.pointerSensitivity, 400, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.pinchCloseRatio, 0.28, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.pinchOpenRatio, 0.38, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.pinchIntentRatio, 0.46, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.quickPinchMaximumDuration, 0.40, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.scrollStabilizationFrames, 1)
        XCTAssertEqual(
            GestureTuning.safeDefaults.pinchMotionActivationDisplacement,
            0.04,
            accuracy: 1e-12
        )
        XCTAssertEqual(GestureTuning.safeDefaults.scrollAxisLockRatio, 1.15, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.scrollSensitivityY, 120, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.zoomSensitivity, 2, accuracy: 1e-12)
        XCTAssertEqual(GestureTuning.safeDefaults.zoomStepThreshold, 0.06, accuracy: 1e-12)
    }

    func testIndexOnlyPointerRequiresStabilityMirrorsAndClutches() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        XCTAssertEqual(events(engine, pointer, at: 0), [])
        XCTAssertEqual(events(engine, pointer, at: 0.139), [])
        XCTAssertEqual(events(engine, pointer, at: 0.140), [])
        assertPointer(events(engine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.160), dx: 2, dy: 0)

        XCTAssertEqual(events(engine, SyntheticHand.pose(.openPalm), at: 0.180), [])
        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.50, dy: 0), at: 0.200), [])
        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.50, dy: 0), at: 0.340), [])
        assertPointer(events(engine, pointer.translatedLocal(dx: 0.47, dy: 0), at: 0.360), dx: -3, dy: 0)

        let mirrored = GestureEngine(tuning: gestureTestTuning())
        _ = events(mirrored, pointer.reflectedAboutPreviewMidline(), at: 0)
        _ = events(mirrored, pointer.reflectedAboutPreviewMidline(), at: 0.14)
        assertPointer(
            events(
                mirrored,
                pointer.translatedLocal(dx: 0.02, dy: 0).reflectedAboutPreviewMidline(),
                at: 0.16
            ),
            dx: -2,
            dy: 0
        )
    }

    func testPointerDeadZoneSuppressesJitterAndEmitsOnlyExcess() {
        var tuning = gestureTestTuning()
        tuning.pointerDeadZone = 0.012
        let engine = GestureEngine(tuning: tuning)
        let pointer = SyntheticHand.pose(.pointer)

        XCTAssertEqual(events(engine, pointer, at: 0), [])
        XCTAssertEqual(events(engine, pointer, at: 0.140), [])
        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.006, dy: 0), at: 0.160), [])
        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.011, dy: 0), at: 0.180), [])
        assertPointer(
            events(engine, pointer.translatedLocal(dx: 0.014, dy: 0), at: 0.200),
            dx: 0.2,
            dy: 0
        )
    }

    func testThumbIndexPinchImmediatelySuppressesActivePointer() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let openPointer = SyntheticHand.pose(.pointer)
        XCTAssertEqual(events(engine, openPointer, at: 0), [])
        let established = result(engine, openPointer, at: 0.140)
        XCTAssertEqual(established.diagnostics.activeGesture, .pointer)
        assertPointer(
            events(engine, openPointer.translatedLocal(dx: 0.02, dy: 0), at: 0.160),
            dx: 2,
            dy: 0
        )

        let closing = openPointer
            .withIndexThumbDistance(0.20)
            .translatedLocal(dx: 0.02, dy: 0.04)
        let result = result(engine, closing, at: 0.180)

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.poses.first?.metrics.pose, .pinch)
        XCTAssertTrue(result.diagnostics.pendingClick)
        XCTAssertEqual(result.diagnostics.activeGesture, .pendingClick)
    }

    func testApproachingPinchFreezesPointerBeforeCloseThreshold() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.140)
        assertPointer(
            events(engine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.160),
            dx: 2,
            dy: 0
        )

        let approaching = pointer
            .withIndexThumbDistance(0.39)
            .translatedLocal(dx: 0.20, dy: 0.10)
        let frozen = result(engine, approaching, at: 0.180)
        XCTAssertEqual(frozen.events, [])
        XCTAssertFalse(frozen.diagnostics.pendingClick)
        XCTAssertEqual(
            frozen.diagnostics.pointerSuppressionReason,
            .middleThumbPinchCandidate
        )
    }

    func testTwoFingerVPoseIsRestAndNeverScrolls() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let v = SyntheticHand.pose(.scroll)
        let first = result(engine, v, at: 0)
        XCTAssertEqual(first.poses.first?.metrics.pose, .unknown)
        XCTAssertEqual(first.diagnostics.activeGesture, .rest)
        XCTAssertEqual(first.events, [])
        XCTAssertEqual(events(engine, v.translatedLocal(dx: 0, dy: 0.20), at: 0.20), [])
    }

    func testQuickPinchReleaseEmitsExactlyOneImmediateClick() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        XCTAssertEqual(events(engine, open, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        let down = result(engine, closed, at: 0.10)
        XCTAssertEqual(down.events, [])
        XCTAssertTrue(down.diagnostics.pendingClick)
        XCTAssertEqual(down.diagnostics.activeGesture, .pendingClick)
        XCTAssertEqual(events(engine, open, at: 0.18), [.leftClick])
        XCTAssertEqual(events(engine, open, at: 0.20), [])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.30)), [])
    }

    func testQuickThumbIndexTapFromPointerEmitsOneClickAndZeroMotion() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let openPointer = SyntheticHand.pose(.pointer)
        let closedPointer = openPointer.withIndexThumbDistance(0.20)

        XCTAssertEqual(events(engine, openPointer, at: 0), [])
        let established = result(engine, openPointer, at: 0.140)
        XCTAssertEqual(established.diagnostics.activeGesture, .pointer)
        assertPointer(
            events(engine, openPointer.translatedLocal(dx: 0.02, dy: 0), at: 0.160),
            dx: 2,
            dy: 0
        )
        let pressed = result(
            engine,
            closedPointer.translatedLocal(dx: 0.02, dy: 0.04),
            at: 0.180
        )
        XCTAssertEqual(pressed.events, [])
        XCTAssertTrue(pressed.diagnostics.pendingClick)

        var trace = pressed.events
        trace += events(
            engine,
            openPointer.translatedLocal(dx: 0.02, dy: 0.04),
            at: 0.240
        )
        trace += events(
            engine,
            openPointer.translatedLocal(dx: 0.02, dy: 0.04),
            at: 0.260
        )

        XCTAssertEqual(trace, [.leftClick])
        XCTAssertEqual(trace.filter(\.isPointer), [])
        XCTAssertEqual(trace.filter(\.isScroll), [])
        XCTAssertEqual(trace.filter(\.isZoom), [])
    }

    func testThumbIndexClickDoesNotRequireMiddleTip() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35)).without(.middleTip)
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20)).without(.middleTip)

        XCTAssertEqual(events(engine, open, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        XCTAssertEqual(events(engine, closed, at: 0.10), [])
        XCTAssertEqual(events(engine, open, at: 0.18), [.leftClick])
    }

    func testWidePinchReleaseOutsideIntentPoseStillCompletesQuickClick() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let wideRelease = SyntheticHand.pose(.pinch(ratio: 0.70))

        XCTAssertEqual(events(engine, open, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        XCTAssertEqual(events(engine, closed, at: 0.10), [])
        let released = result(engine, wideRelease, at: 0.18)
        XCTAssertNotEqual(released.poses.first?.metrics.pose, .pinch)
        XCTAssertEqual(released.events, [.leftClick])
    }

    func testStartingClosedIsBlockedUntilOpenRearm() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))

        XCTAssertEqual(events(engine, closed, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.40), [])
        XCTAssertEqual(events(engine, open, at: 0.47), [])
        XCTAssertEqual(events(engine, closed, at: 0.50), [])
        XCTAssertEqual(events(engine, open, at: 0.60), [.leftClick])
    }

    func testHeldStationaryPinchNeverClicksOrEmitsLegacyActions() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        var trace: [GestureEvent] = []

        trace += events(engine, open, at: 0)
        trace += events(engine, open, at: 0.07)
        trace += events(engine, closed, at: 0.10)
        trace += events(engine, closed, at: 0.28)
        trace += events(engine, closed, at: 0.41)
        trace += events(engine, closed, at: 0.90)
        trace += events(engine, open, at: 1.00)

        XCTAssertEqual(trace, [])
        assertNoLegacyEvents(trace)
    }

    func testVerticalPinchMotionPromotesScrollAndSuppressesClickOnRelease() {
        let engine = armedPinchEngine()
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))

        XCTAssertEqual(events(engine, closed.translatedLocal(dx: 0, dy: 0.04), at: 0.16), [])
        let promoted = result(engine, closed.translatedLocal(dx: 0, dy: 0.07), at: 0.18)
        assertScroll(promoted.events, dy: 1)
        XCTAssertEqual(promoted.diagnostics.activeGesture, .scroll)
        XCTAssertEqual(promoted.diagnostics.scrollDisplacement ?? 0, 0.07, accuracy: 1e-9)
        assertScroll(events(engine, closed.translatedLocal(dx: 0, dy: 0.09), at: 0.20), dy: 2)
        XCTAssertEqual(events(engine, open.translatedLocal(dx: 0, dy: 0.09), at: 0.22), [])
    }

    func testHeldPinchRequiresActivationAndHorizontalMotionZooms() {
        let held = armedPinchEngine()
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        XCTAssertEqual(events(held, closed.translatedLocal(dx: 0, dy: 0.05), at: 0.40), [])
        XCTAssertEqual(events(
            held,
            SyntheticHand.pose(.pinch(ratio: 0.35)).translatedLocal(dx: 0, dy: 0.05),
            at: 0.60
        ), [])

        let horizontal = armedPinchEngine()
        assertZoom(
            events(horizontal, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.18),
            delta: 0.02
        )
        XCTAssertEqual(events(
            horizontal,
            SyntheticHand.pose(.pinch(ratio: 0.35)).translatedLocal(dx: 0.08, dy: 0),
            at: 0.22
        ), [])
    }

    func testPinchUsesStableWristAnchorAndIgnoresTwoStabilizationFrames() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        XCTAssertEqual(events(engine, open, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        XCTAssertEqual(events(engine, closed, at: 0.10), [])

        // These are fingertip-only movements. A wrist/palm anchor must not see
        // them as downward scrolling, and both stabilization frames are quiet.
        let fingertipMotion = closed.movingIndexThumbTips(dx: 0, dy: 0.12)
        XCTAssertEqual(events(engine, fingertipMotion, at: 0.12), [])
        XCTAssertEqual(events(engine, fingertipMotion, at: 0.14), [])

        let belowActivation = fingertipMotion.translatedLocal(dx: 0, dy: 0.05)
        XCTAssertEqual(events(engine, belowActivation, at: 0.16), [])
        let promoted = result(
            engine,
            fingertipMotion.translatedLocal(dx: 0, dy: 0.07),
            at: 0.18
        )
        assertScroll(promoted.events, dy: 1)
        XCTAssertEqual(promoted.diagnostics.activeGesture, .scroll)
        XCTAssertEqual(promoted.diagnostics.scrollDisplacement ?? 0, 0.07, accuracy: 1e-9)
        XCTAssertEqual(promoted.diagnostics.scrollVerticalDelta ?? 0, 0.02, accuracy: 1e-9)
    }

    func testTwoHandsAreNeutralAndNeverEmitZoomOrClick() {
        let engine = armedPinchEngine(includeStabilizationFrames: false)
        var trace: [GestureEvent] = []

        trace += engine.process(trackingFrame(
            time: 0.12,
            hands: [
                SyntheticHand.pose(.pinch(ratio: 0.20)).translatedLocal(dx: -1.2, dy: 0).tracked(id: 11, at: 0.12),
                SyntheticHand.pose(.pinch(ratio: 0.35)).translatedLocal(dx: 1.2, dy: 0).tracked(id: 22, at: 0.12)
            ]
        )).events
        trace += zoomEvents(engine, time: 0.19, ratio: 0.35, a: 1.2)
        trace += zoomEvents(engine, time: 0.22, ratio: 0.20, a: 1.2)
        trace += zoomEvents(engine, time: 0.36, ratio: 0.20, a: 1.2)
        trace += zoomEvents(engine, time: 0.38, ratio: 0.20, a: 1.5)

        XCTAssertEqual(trace, [])
        XCTAssertFalse(trace.contains(.leftClick))
        assertNoLegacyEvents(trace)
    }

    func testOneHandHorizontalPinchMapsRightToZoomInAndLeftToZoomOut() {
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let right = armedPinchEngine()
        assertZoom(
            events(right, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.16),
            delta: 0.02
        )
        assertZoom(
            events(right, closed.translatedLocal(dx: 0.10, dy: 0), at: 0.18),
            delta: 0.02
        )

        let left = armedPinchEngine()
        assertZoom(
            events(left, closed.translatedLocal(dx: -0.08, dy: 0), at: 0.16),
            delta: -0.02
        )
    }

    func testPinchAxisLocksAndDiagonalMotionNeverLeaksClick() {
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let horizontal = armedPinchEngine()
        assertZoom(
            events(horizontal, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.16),
            delta: 0.02
        )
        XCTAssertEqual(
            events(horizontal, closed.translatedLocal(dx: 0.08, dy: 0.20), at: 0.18),
            []
        )
        assertZoom(
            events(horizontal, closed.translatedLocal(dx: 0.10, dy: 0.20), at: 0.20),
            delta: 0.02
        )

        let diagonal = armedPinchEngine()
        XCTAssertEqual(
            events(diagonal, closed.translatedLocal(dx: 0.08, dy: 0.08), at: 0.16),
            []
        )
        XCTAssertEqual(
            events(diagonal, open.translatedLocal(dx: 0.08, dy: 0.08), at: 0.20),
            []
        )
    }

    func testLocalDegradationRestartsPointerAndReanchorsHorizontalZoom() {
        let pointerEngine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        XCTAssertEqual(events(pointerEngine, pointer, at: 0), [])
        XCTAssertEqual(pointerEngine.process(trackingFrame(
            time: 0.10,
            hands: [pointer.tracked(at: 0.10)],
            quality: .degraded,
            degradationReason: .poseAmbiguity
        )).events, [])
        XCTAssertEqual(events(pointerEngine, pointer, at: 0.14), [])
        XCTAssertEqual(events(pointerEngine, pointer, at: 0.279), [])
        XCTAssertEqual(events(pointerEngine, pointer, at: 0.280), [])
        assertPointer(
            events(pointerEngine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.30),
            dx: 2,
            dy: 0
        )

        let zoomEngine = armedPinchEngine()
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        assertZoom(
            events(zoomEngine, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.16),
            delta: 0.02
        )
        let degradedZoom = zoomEngine.process(trackingFrame(
            time: 0.18,
            hands: [closed.translatedLocal(dx: 0.50, dy: 0).tracked(at: 0.18)],
            quality: .degraded,
            degradationReason: .poseAmbiguity
        ))
        XCTAssertEqual(degradedZoom.events, [])
        XCTAssertEqual(events(
            zoomEngine,
            closed.translatedLocal(dx: 0.50, dy: 0),
            at: 0.20
        ), [])
        assertZoom(
            events(zoomEngine, closed.translatedLocal(dx: 0.52, dy: 0), at: 0.22),
            delta: 0.02
        )
    }

    func testMissingRequiredPinchJointReportsMissingConfidence() {
        let engine = armedPinchEngine()
        let result = result(
            engine,
            SyntheticHand.pose(.pinch(ratio: 0.20)).without(.thumbTip),
            at: 0.16
        )

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.diagnostics.degradationReason, .lowRequiredJointConfidence)
        XCTAssertNil(result.diagnostics.requiredJointConfidence)
    }

    func testRequiredPointerJointDipFreezesAndReanchorsWithoutTrackingLoss() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.14)
        assertPointer(events(engine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.16), dx: 2, dy: 0)

        let dipped = pointer.translatedLocal(dx: 0.50, dy: 0)
            .withConfidence(0.59, for: .indexTip)
        let frozen = result(engine, dipped, at: 0.18)
        XCTAssertEqual(frozen.events, [])
        XCTAssertEqual(frozen.diagnostics.degradationReason, .lowRequiredJointConfidence)

        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.50, dy: 0), at: 0.20), [])
        assertPointer(events(engine, pointer.translatedLocal(dx: 0.52, dy: 0), at: 0.22), dx: 2, dy: 0)
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.30)), [])
    }

    func testRequiredPinchJointDipFreezesScrollAndReanchors() {
        let engine = armedPinchEngine()
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        assertScroll(events(engine, closed.translatedLocal(dx: 0, dy: 0.07), at: 0.16), dy: 1)

        let dipped = closed.translatedLocal(dx: 0, dy: 0.50)
            .withConfidence(0.59, for: .thumbTip)
        XCTAssertEqual(events(engine, dipped, at: 0.18), [])
        XCTAssertEqual(events(engine, closed.translatedLocal(dx: 0, dy: 0.50), at: 0.20), [])
        assertScroll(events(engine, closed.translatedLocal(dx: 0, dy: 0.52), at: 0.22), dy: 2)
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.30)), [])
    }

    func testPendingPinchRecoveryAndDiscontinuityResetScrollOrigin() {
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        let confidenceDip = armedPinchEngine()
        let dipped = closed.translatedLocal(dx: 0, dy: 0.50)
            .withConfidence(0.59, for: .thumbTip)
        XCTAssertEqual(events(confidenceDip, dipped, at: 0.16), [])
        XCTAssertEqual(events(
            confidenceDip,
            closed.translatedLocal(dx: 0, dy: 0.50),
            at: 0.18
        ), [])
        XCTAssertEqual(events(
            confidenceDip,
            closed.translatedLocal(dx: 0, dy: 0.52),
            at: 0.20
        ), [])
        XCTAssertEqual(events(
            confidenceDip,
            closed.translatedLocal(dx: 0, dy: 0.52),
            at: 0.22
        ), [])
        assertScroll(
            events(confidenceDip, closed.translatedLocal(dx: 0, dy: 0.59), at: 0.24),
            dy: 1
        )

        let discontinuity = armedPinchEngine()
        XCTAssertEqual(events(
            discontinuity,
            closed.translatedLocal(dx: 0, dy: 0.50),
            at: 0.16
        ), [])
        XCTAssertEqual(events(
            discontinuity,
            closed.translatedLocal(dx: 0, dy: 0.52),
            at: 0.18
        ), [])
        XCTAssertEqual(events(
            discontinuity,
            closed.translatedLocal(dx: 0, dy: 0.52),
            at: 0.20
        ), [])
        assertScroll(
            events(discontinuity, closed.translatedLocal(dx: 0, dy: 0.59), at: 0.22),
            dy: 1
        )
    }

    func testLowUnrelatedThumbJointDoesNotInterruptPointer() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.14)
        let lowThumb = pointer.translatedLocal(dx: 0.02, dy: 0)
            .withConfidence(0.10, for: .thumbTip)
        assertPointer(events(engine, lowThumb, at: 0.16), dx: 2, dy: 0)
    }

    func testWholeHandConfidenceSummaryDoesNotTurnLocalOcclusionIntoGlobalLoss() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer).withObservationConfidence(0.10)

        XCTAssertEqual(events(engine, pointer, at: 0), [])
        XCTAssertEqual(events(engine, pointer, at: 0.14), [])
        assertPointer(
            events(engine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.16),
            dx: 2,
            dy: 0
        )
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.25)), [])
    }

    func testRetainedMissingSecondTrackDoesNotBlockValidOneHandPointer() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)

        func frame(time: Double, dx: Double = 0) -> TrackingSnapshot {
            trackingFrame(time: time, hands: [
                pointer.translatedLocal(dx: dx, dy: 0).tracked(id: 1, at: time),
                SyntheticHand.pose(.openPalm).tracked(
                    id: 2,
                    at: time,
                    associationCertain: false,
                    missingDuration: 0.05
                )
            ])
        }

        XCTAssertEqual(engine.process(frame(time: 0)).events, [])
        XCTAssertEqual(engine.process(frame(time: 0.14)).events, [])
        assertPointer(engine.process(frame(time: 0.16, dx: 0.02)).events, dx: 2, dy: 0)
    }

    func testPointerUsesProximalFoldedEvidenceWhenFingerTipsAreLowOrAbsent() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
            .withConfidence(0.10, for: .middleTip)
            .without(.ringTip)
            .withConfidence(0.10, for: .littleTip)

        let initial = result(engine, pointer, at: 0)
        XCTAssertEqual(initial.poses.first?.metrics.pose, .pointer)
        XCTAssertEqual(initial.poses.first?.metrics.minimumRequiredConfidence ?? 0, 0.95)
        XCTAssertEqual(events(engine, pointer, at: 0.14), [])
        assertPointer(events(engine, pointer.translatedLocal(dx: 0.02, dy: 0), at: 0.16), dx: 2, dy: 0)
    }

    func testPinchIgnoresThumbCMCAndOccludedFoldedFingerTips() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = occlusionTolerantPinch(ratio: 0.35)
        let closed = occlusionTolerantPinch(ratio: 0.20)

        let initial = result(engine, open, at: 0)
        XCTAssertNotEqual(initial.poses.first?.metrics.pose, .fist)
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        let pressed = result(engine, closed, at: 0.10)
        XCTAssertEqual(pressed.poses.first?.metrics.pose, .pinch)
        XCTAssertEqual(pressed.poses.first?.metrics.minimumRequiredConfidence ?? 0, 0.95)
        XCTAssertEqual(pressed.events, [])
        XCTAssertEqual(events(engine, open, at: 0.18), [.leftClick])
    }

    func testThumbIndexPinchTakesPriorityOverFistAndPointer() {
        let classifier = HandPoseClassifier()
        let closedFistGeometry = SyntheticHand.pose(.fist).withIndexThumbDistance(0.20)
        let likelyContact = SyntheticHand.pose(.fist).withIndexThumbDistance(0.27)
        let pointerGeometry = closedFistGeometry.withIndexExtended()

        let closedMetrics = classifier.classify(closedFistGeometry.tracked(at: 0))
        XCTAssertEqual(closedMetrics.pinchRatio ?? -1, 0.20, accuracy: 1e-12)
        XCTAssertEqual(closedMetrics.pose, .pinch)
        XCTAssertNotEqual(classifier.classify(likelyContact.tracked(at: 0)).pose, .fist)
        XCTAssertEqual(classifier.classify(pointerGeometry.tracked(at: 0)).pose, .pinch)
        XCTAssertEqual(classifier.classify(SyntheticHand.pose(.fist).tracked(at: 0)).pose, .fist)
    }

    func testActiveThumbIndexPinchHysteresisNeverFallsThroughToFist() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        XCTAssertEqual(events(engine, open, at: 0), [])
        XCTAssertEqual(events(engine, open, at: 0.07), [])
        XCTAssertEqual(events(engine, SyntheticHand.pose(.pinch(ratio: 0.20)), at: 0.10), [])

        let ambiguous = result(engine, SyntheticHand.pose(.pinch(ratio: 0.27)), at: 0.12)
        XCTAssertNotEqual(ambiguous.poses.first?.metrics.pose, .fist)
        XCTAssertTrue(ambiguous.diagnostics.pendingClick)
        XCTAssertEqual(ambiguous.diagnostics.activeGesture, .pendingClick)
        XCTAssertEqual(ambiguous.events, [])
    }

    func testFistWithOccludedTipIsSafeRestNotGlobalTrackingLoss() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let fist = SyntheticHand.pose(.fist).without(.ringTip)
        let frame = result(engine, fist, at: 0)
        XCTAssertEqual(frame.events, [])
        XCTAssertEqual(frame.diagnostics.activeGesture, .rest)
        XCTAssertEqual(engine.advance(to: .init(rawValue: 1)), [])
    }

    func testContinuousNoHandFramesStayNeutralAndReliableReturnReanchors() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.14)
        for time in [0.16, 0.32, 0.48, 0.64, 0.80] {
            let missing = engine.process(trackingFrame(time: time, hands: [], quality: .absent))
            XCTAssertEqual(missing.events, [])
            XCTAssertEqual(missing.diagnostics.pointerSuppressionReason, .trackingUnavailable)
        }

        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.50, dy: 0), at: 0.82), [])
        XCTAssertEqual(events(engine, pointer.translatedLocal(dx: 0.50, dy: 0), at: 0.96), [])
        assertPointer(
            events(engine, pointer.translatedLocal(dx: 0.52, dy: 0), at: 0.98),
            dx: 2,
            dy: 0
        )
    }

    func testFreshNoHandFrameResetsTrueNoFrameDeadline() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.14)
        XCTAssertEqual(
            engine.process(trackingFrame(time: 0.80, hands: [], quality: .absent)).events,
            []
        )

        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.9499)), [])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.9500)), [.trackingLost])
    }

    func testGenuineNoFrameStallEmitsOneTrackingLostAt150Milliseconds() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = events(engine, pointer, at: 0)
        _ = events(engine, pointer, at: 0.14)
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.2899)), [])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.2900)), [.trackingLost])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 1)), [])
    }

    func testTrackingLossClearsPendingMiddlePinchAndCannotLeakClickOrScroll() {
        let engine = armedPinchEngine(includeStabilizationFrames: false)
        let missing = engine.process(trackingFrame(time: 0.12, hands: [], quality: .absent))
        XCTAssertEqual(missing.events, [])
        XCTAssertFalse(missing.diagnostics.pendingClick)
        XCTAssertEqual(missing.diagnostics.activeGesture, .rest)
        XCTAssertTrue(engine.debugStateDescription.contains("gesture=rest"))

        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.2699)), [])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.2700)), [.trackingLost])
        XCTAssertEqual(engine.advance(to: .init(rawValue: 0.40)), [])

        let released = SyntheticHand.pose(.pinch(ratio: 0.35))
            .translatedLocal(dx: 0, dy: 0.20)
        XCTAssertEqual(events(engine, released, at: 0.42), [])
    }

    func testActiveHorizontalZoomHasNoTailAfterWatchdogOrEmergency() {
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        let watchdogEngine = armedPinchEngine()
        assertZoom(
            events(watchdogEngine, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.16),
            delta: 0.02
        )
        XCTAssertEqual(
            watchdogEngine.advance(to: .init(rawValue: 0.31)),
            [.trackingLost]
        )
        XCTAssertEqual(
            events(watchdogEngine, closed.translatedLocal(dx: 0.50, dy: 0), at: 0.32),
            []
        )

        let emergencyEngine = armedPinchEngine()
        assertZoom(
            events(emergencyEngine, closed.translatedLocal(dx: 0.08, dy: 0), at: 0.16),
            delta: 0.02
        )
        XCTAssertEqual(emergencyEngine.reset(reason: .emergency), [])
        XCTAssertEqual(
            events(emergencyEngine, closed.translatedLocal(dx: 0.50, dy: 0), at: 0.18),
            []
        )
    }

    func testActiveVerticalScrollHasNoTailAfterWatchdogOrEmergency() {
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        let watchdogEngine = armedPinchEngine()
        assertScroll(
            events(watchdogEngine, closed.translatedLocal(dx: 0, dy: 0.07), at: 0.18),
            dy: 1
        )
        XCTAssertEqual(
            watchdogEngine.advance(to: .init(rawValue: 0.33)),
            [.trackingLost]
        )
        XCTAssertEqual(
            events(watchdogEngine, closed.translatedLocal(dx: 0, dy: 0.50), at: 0.34),
            []
        )

        let emergencyEngine = armedPinchEngine()
        assertScroll(
            events(emergencyEngine, closed.translatedLocal(dx: 0, dy: 0.07), at: 0.18),
            dy: 1
        )
        XCTAssertEqual(emergencyEngine.reset(reason: .emergency), [])
        XCTAssertEqual(
            events(emergencyEngine, closed.translatedLocal(dx: 0, dy: 0.50), at: 0.20),
            []
        )
    }

    func testEmergencyAndDisableResetClearPendingStateWithoutLegacyCleanup() {
        for reason in [GestureResetReason.emergency, .disabled, .paused] {
            let engine = armedPinchEngine(includeStabilizationFrames: false)
            XCTAssertEqual(engine.reset(reason: reason), [])
            XCTAssertEqual(engine.reset(reason: reason), [])
            XCTAssertTrue(engine.debugStateDescription.contains("gesture=rest"))
            let open = SyntheticHand.pose(.pinch(ratio: 0.35))
            let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
            XCTAssertEqual(events(engine, open, at: 0.90), [])
            XCTAssertEqual(events(engine, closed.translatedLocal(dx: 0, dy: 0.20), at: 1), [])
            XCTAssertEqual(events(engine, open.translatedLocal(dx: 0, dy: 0.20), at: 1.10), [])
        }
    }

    func testEngineNeverEmitsDoubleClickDragOrRightClick() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        var trace: [GestureEvent] = []
        trace += events(engine, open, at: 0)
        trace += events(engine, open, at: 0.07)
        trace += events(engine, closed, at: 0.10)
        trace += events(engine, closed.translatedLocal(dx: 0.20, dy: 0.20), at: 0.20)
        trace += events(engine, closed, at: 0.80)
        trace += events(engine, open, at: 0.90)
        assertNoLegacyEvents(trace)
    }

    private func armedPinchEngine(includeStabilizationFrames: Bool = true) -> GestureEngine {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        _ = events(engine, open, at: 0)
        _ = events(engine, open, at: 0.07)
        _ = events(engine, closed, at: 0.10)
        if includeStabilizationFrames {
            _ = events(engine, closed, at: 0.12)
            _ = events(engine, closed, at: 0.14)
        }
        return engine
    }

    private func armedZoomEngine() -> GestureEngine {
        let engine = GestureEngine(tuning: gestureTestTuning())
        _ = zoomEvents(engine, time: 0, ratio: 0.35, a: 1.2)
        _ = zoomEvents(engine, time: 0.07, ratio: 0.35, a: 1.2)
        _ = zoomEvents(engine, time: 0.10, ratio: 0.20, a: 1.2)
        _ = zoomEvents(engine, time: 0.24, ratio: 0.20, a: 1.2)
        return engine
    }

    private func events(
        _ engine: GestureEngine,
        _ hand: SyntheticHand,
        at time: Double
    ) -> [GestureEvent] {
        result(engine, hand, at: time).events
    }

    private func result(
        _ engine: GestureEngine,
        _ hand: SyntheticHand,
        at time: Double
    ) -> GestureFrameResult {
        engine.process(trackingFrame(time: time, hands: [hand.tracked(at: time)]))
    }

    private func zoomEvents(
        _ engine: GestureEngine,
        time: Double,
        ratio: Double,
        a: Double
    ) -> [GestureEvent] {
        engine.process(trackingFrame(
            time: time,
            hands: zoomHands(time: time, ratio: ratio, halfSeparation: a)
        )).events
    }

    private func occlusionTolerantPinch(ratio: Double) -> SyntheticHand {
        SyntheticHand.pose(.pinch(ratio: ratio))
            .withConfidence(0.10, for: .thumbCMC)
            .without(.middleTip)
            .withConfidence(0.10, for: .ringTip)
            .without(.littleTip)
    }

    private func occludedZoomEvents(
        _ engine: GestureEngine,
        time: Double,
        ratio: Double,
        a: Double
    ) -> [GestureEvent] {
        engine.process(trackingFrame(
            time: time,
            hands: [
                occlusionTolerantPinch(ratio: ratio)
                    .translatedLocal(dx: -a, dy: 0)
                    .tracked(id: 11, at: time),
                occlusionTolerantPinch(ratio: ratio)
                    .translatedLocal(dx: a, dy: 0)
                    .tracked(id: 22, at: time)
            ]
        )).events
    }

    private func assertPointer(
        _ events: [GestureEvent],
        dx: Double,
        dy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard events.count == 1, case let .pointerDelta(actualX, actualY) = events[0] else {
            return XCTFail("Expected pointer delta, got \(events)", file: file, line: line)
        }
        XCTAssertEqual(actualX, dx, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualY, dy, accuracy: 1e-9, file: file, line: line)
    }

    private func assertScroll(
        _ events: [GestureEvent],
        dy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard events.count == 1, case let .scroll(dx, actualY) = events[0] else {
            return XCTFail("Expected vertical scroll, got \(events)", file: file, line: line)
        }
        XCTAssertEqual(dx, 0, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualY, dy, accuracy: 1e-9, file: file, line: line)
    }

    private func assertZoom(
        _ events: [GestureEvent],
        delta: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard events.count == 1, case let .zoom(actual) = events[0] else {
            return XCTFail("Expected zoom, got \(events)", file: file, line: line)
        }
        XCTAssertEqual(actual, delta, accuracy: 1e-9, file: file, line: line)
    }

    private func assertNoLegacyEvents(
        _ events: [GestureEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for event in events {
            switch event {
            case .doubleClick, .dragStart, .dragDelta, .dragEnd, .rightClick:
                XCTFail("Legacy event escaped: \(event)", file: file, line: line)
            case .pointerDelta, .leftClick, .scroll, .zoom, .trackingLost:
                break
            }
        }
    }
}

private extension GestureEvent {
    var isPointer: Bool {
        if case .pointerDelta = self { return true }
        return false
    }

    var isScroll: Bool {
        if case .scroll = self { return true }
        return false
    }

    var isZoom: Bool {
        if case .zoom = self { return true }
        return false
    }
}
