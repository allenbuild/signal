import CoreGraphics
import XCTest
@testable import Signal

final class InputControllerTests: XCTestCase {
    func testGesturePipelineClutchesPointerBeforePinchAndScrollOutput() {
        let sink = PipelineClutchSpy()
        let pipeline = GesturePipeline(tuning: gestureTestTuning(), inputSink: sink)
        let pointer = SyntheticHand.pose(.pointer)

        _ = pipeline.process(trackingFrame(time: 0, hands: [pointer.tracked(at: 0)]))
        _ = pipeline.process(trackingFrame(time: 0.14, hands: [pointer.tracked(at: 0.14)]))
        _ = pipeline.process(trackingFrame(
            time: 0.16,
            hands: [pointer.translatedLocal(dx: 0.02, dy: 0).tracked(at: 0.16)]
        ))
        XCTAssertTrue(sink.actions.contains { action in
            if case .event(.pointerDelta) = action { return true }
            return false
        })
        sink.clear()

        let closed = pointer.withMiddleThumbDistance(0.20)
            .translatedLocal(dx: 0.02, dy: 0.04)
        let pressed = pipeline.process(trackingFrame(
            time: 0.18,
            hands: [closed.tracked(at: 0.18)]
        ))
        XCTAssertTrue(pressed.diagnostics.pendingClick)
        XCTAssertEqual(sink.actions, [.clutch])

        _ = pipeline.process(trackingFrame(time: 0.20, hands: [closed.tracked(at: 0.20)]))
        _ = pipeline.process(trackingFrame(time: 0.22, hands: [closed.tracked(at: 0.22)]))
        let scrolled = pipeline.process(trackingFrame(
            time: 0.24,
            hands: [closed.translatedLocal(dx: 0, dy: 0.07).tracked(at: 0.24)]
        ))
        XCTAssertEqual(scrolled.diagnostics.activeGesture, .scroll)
        let tail = Array(sink.actions.suffix(2))
        XCTAssertEqual(tail.first, .clutch)
        guard tail.count == 2, case let .event(.scroll(dx, dy)) = tail[1] else {
            return XCTFail("Expected clutch immediately before scroll, got \(tail)")
        }
        XCTAssertEqual(dx, 0, accuracy: 1e-9)
        XCTAssertEqual(dy, 1, accuracy: 1e-9)
    }

    func testGesturePipelineClutchesQueuedMotionOnTrackingDegradation() {
        let sink = PipelineClutchSpy()
        let pipeline = GesturePipeline(tuning: gestureTestTuning(), inputSink: sink)
        let pointer = SyntheticHand.pose(.pointer)

        _ = pipeline.process(trackingFrame(time: 0, hands: [pointer.tracked(at: 0)]))
        _ = pipeline.process(trackingFrame(time: 0.14, hands: [pointer.tracked(at: 0.14)]))
        _ = pipeline.process(trackingFrame(
            time: 0.16,
            hands: [pointer.translatedLocal(dx: 0.02, dy: 0).tracked(at: 0.16)]
        ))
        sink.clear()

        let degraded = pipeline.process(trackingFrame(
            time: 0.18,
            hands: [],
            quality: .absent,
            degradationReason: .noHandDetected
        ))

        XCTAssertEqual(degraded.diagnostics.pointerSuppressionReason, .trackingUnavailable)
        XCTAssertEqual(sink.actions, [.suspend])
    }

    func testActiveHorizontalZoomNoHandSuspendsAndRequiresFreshRearm() {
        var tuning = gestureTestTuning()
        tuning.scrollStabilizationFrames = 0
        let sink = PipelineClutchSpy()
        let pipeline = GesturePipeline(tuning: tuning, inputSink: sink)
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        _ = pipeline.process(trackingFrame(time: 0, hands: [open.tracked(at: 0)]))
        _ = pipeline.process(trackingFrame(time: 0.07, hands: [open.tracked(at: 0.07)]))
        _ = pipeline.process(trackingFrame(time: 0.10, hands: [closed.tracked(at: 0.10)]))
        let zooming = pipeline.process(trackingFrame(
            time: 0.18,
            hands: [closed.translatedLocal(dx: 0.08, dy: 0).tracked(at: 0.18)]
        ))
        XCTAssertEqual(zooming.diagnostics.activeGesture, .zoom)
        XCTAssertTrue(sink.actions.contains { action in
            if case let .event(.zoom(delta)) = action {
                return abs(delta - 0.02) < 1e-9
            }
            return false
        })
        sink.clear()

        let absent = pipeline.process(trackingFrame(
            time: 0.20,
            hands: [],
            quality: .absent,
            degradationReason: .noHandDetected
        ))
        XCTAssertEqual(absent.events, [])
        XCTAssertEqual(sink.actions, [.suspend])
        sink.clear()

        // Returning while still pinched is deliberately inert. Opening and
        // stabilizing starts a wholly new episode with a new anchor.
        _ = pipeline.process(trackingFrame(
            time: 0.22,
            hands: [closed.translatedLocal(dx: 0.50, dy: 0).tracked(at: 0.22)]
        ))
        XCTAssertFalse(sink.actions.contains { action in
            if case .event = action { return true }
            return false
        })
        _ = pipeline.process(trackingFrame(
            time: 0.24,
            hands: [open.translatedLocal(dx: 0.50, dy: 0).tracked(at: 0.24)]
        ))
        _ = pipeline.process(trackingFrame(
            time: 0.31,
            hands: [open.translatedLocal(dx: 0.50, dy: 0).tracked(at: 0.31)]
        ))
        _ = pipeline.process(trackingFrame(
            time: 0.34,
            hands: [closed.translatedLocal(dx: 0.50, dy: 0).tracked(at: 0.34)]
        ))
        sink.clear()
        let rearmed = pipeline.process(trackingFrame(
            time: 0.42,
            hands: [closed.translatedLocal(dx: 0.58, dy: 0).tracked(at: 0.42)]
        ))
        XCTAssertEqual(rearmed.diagnostics.activeGesture, .zoom)
        XCTAssertTrue(sink.actions.contains { action in
            if case let .event(.zoom(delta)) = action {
                return abs(delta - 0.02) < 1e-9
            }
            return false
        })
    }

    func testActiveVerticalScrollNoHandSuspendsWithoutTail() {
        var tuning = gestureTestTuning()
        tuning.scrollStabilizationFrames = 0
        let sink = PipelineClutchSpy()
        let pipeline = GesturePipeline(tuning: tuning, inputSink: sink)
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        _ = pipeline.process(trackingFrame(time: 0, hands: [open.tracked(at: 0)]))
        _ = pipeline.process(trackingFrame(time: 0.07, hands: [open.tracked(at: 0.07)]))
        _ = pipeline.process(trackingFrame(time: 0.10, hands: [closed.tracked(at: 0.10)]))
        let scrolling = pipeline.process(trackingFrame(
            time: 0.18,
            hands: [closed.translatedLocal(dx: 0, dy: 0.07).tracked(at: 0.18)]
        ))
        XCTAssertEqual(scrolling.diagnostics.activeGesture, .scroll)
        sink.clear()

        let absent = pipeline.process(trackingFrame(
            time: 0.20,
            hands: [],
            quality: .absent,
            degradationReason: .noHandDetected
        ))
        XCTAssertEqual(absent.events, [])
        XCTAssertEqual(sink.actions, [.suspend])
        sink.clear()

        let returnedClosed = pipeline.process(trackingFrame(
            time: 0.22,
            hands: [closed.translatedLocal(dx: 0, dy: 0.50).tracked(at: 0.22)]
        ))
        XCTAssertEqual(returnedClosed.events, [])
        XCTAssertFalse(sink.actions.contains { action in
            if case .event = action { return true }
            return false
        })
    }

    func testOutputStartsDisabledAndTrustBlocksEveryGeneratedEvent() {
        let backend = FakeInputBackend()
        let trust = FakeInputTrustProvider(trusted: false, canPost: false)
        let controller = makeController(backend: backend, trust: trust)

        XCTAssertFalse(controller.isOutputEnabled)
        controller.handle(.leftClick)
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        controller.setOutputGate(enabled: true)
        drain(controller)
        XCTAssertFalse(controller.isOutputEnabled)
        controller.handle(.pointerDelta(dx: 10, dy: -5))
        drain(controller)
        XCTAssertEqual(backend.events(), [])
        XCTAssertEqual(controller.snapshot().heldButtons, [])
    }

    func testTransientClutchNeverEnablesDisabledOrInvalidatesPendingEnable() {
        let backend = ClutchBlockingInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )

        let disabledGeneration = controller.currentGeneration
        controller.clutchPendingNormalOutput()
        XCTAssertFalse(controller.isOutputEnabled)
        XCTAssertEqual(controller.currentGeneration, disabledGeneration)

        backend.blockHealthCheck()
        controller.setOutputGate(enabled: true)
        XCTAssertTrue(backend.waitUntilHealthCheckIsBlocked())
        let pendingGeneration = controller.currentGeneration

        controller.clutchPendingNormalOutput()
        XCTAssertFalse(controller.isOutputEnabled)
        XCTAssertEqual(controller.currentGeneration, pendingGeneration)

        backend.resumeHealthCheck()
        drain(controller)
        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(controller.currentGeneration, pendingGeneration)
        XCTAssertEqual(backend.events(), [])
    }

    func testTransientClutchInvalidatesQueuedPointerWhilePreservingAcceptingGate() {
        let backend = ClutchBlockingInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )
        enable(controller)

        backend.blockCursorRead()
        controller.handle(.pointerDelta(dx: 25, dy: 10))
        XCTAssertTrue(backend.waitUntilCursorReadIsBlocked())
        let previousGeneration = controller.currentGeneration
        let clutchCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            controller.clutchPendingNormalOutput()
            clutchCompleted.signal()
        }

        XCTAssertTrue(waitUntil { controller.currentGeneration > previousGeneration })
        backend.resumeCursorRead()
        XCTAssertEqual(clutchCompleted.wait(timeout: .now() + 1), .success)
        drain(controller)

        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(controller.currentGeneration, previousGeneration + 1)
        XCTAssertEqual(backend.events(), [])
    }

    func testTransientClutchClearsScrollAndZoomAccumulators() {
        var tuning = GestureTuning.safeDefaults
        tuning.naturalScrolling = false
        tuning.zoomStepThreshold = 0.08
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend, tuning: tuning)

        controller.handle(.scroll(dx: 0.6, dy: 0.6))
        controller.handle(.zoom(delta: 0))
        controller.handle(.zoom(delta: 0.05))
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        controller.clutchPendingNormalOutput()
        controller.handle(.scroll(dx: 0.5, dy: 0.5))
        controller.handle(.zoom(delta: 0.05))
        drain(controller)

        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(backend.events(), [])

        controller.suspendForTrackingUnavailable()
        controller.handle(.zoom(delta: 0.05))
        drain(controller)

        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(backend.events(), [])
    }

    func testTrackingSuspensionClearsRealZoomAccumulator() {
        var tuning = GestureTuning.safeDefaults
        tuning.zoomStepThreshold = 0.08
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend, tuning: tuning)

        controller.handle(.zoom(delta: 0))
        controller.handle(.zoom(delta: 0.05))
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        controller.suspendForTrackingUnavailable()
        controller.handle(.zoom(delta: 0))
        controller.handle(.zoom(delta: 0.05))
        drain(controller)

        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(backend.events(), [])
    }

    func testTrackingSuspensionClearsRealScrollAccumulator() {
        var tuning = GestureTuning.safeDefaults
        tuning.naturalScrolling = false
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend, tuning: tuning)

        controller.handle(.scroll(dx: 0.6, dy: 0.6))
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        controller.suspendForTrackingUnavailable()
        controller.handle(.scroll(dx: 0.5, dy: 0.5))
        drain(controller)

        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(backend.events(), [])
    }

    func testTrackingSuspensionPreservesEnableAndSynchronouslyReleasesHeldInput() {
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend)
        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(controller.snapshot().heldButtons, [.left])

        let previousGeneration = controller.currentGeneration
        controller.suspendForTrackingUnavailable()

        let snapshot = controller.snapshot()
        XCTAssertTrue(snapshot.outputEnabled)
        XCTAssertEqual(snapshot.generation, previousGeneration + 1)
        XCTAssertEqual(snapshot.heldButtons, [])
        XCTAssertEqual(snapshot.possiblyHeldButtons, [])
        XCTAssertEqual(backend.events(), [
            .mouse(
                kind: .leftDown,
                position: Point2D(x: 100, y: 100),
                button: .left,
                clickState: 1
            ),
            .mouse(
                kind: .leftUp,
                position: Point2D(x: 100, y: 100),
                button: .left,
                clickState: 1
            )
        ])
    }

    func testFailedTrackingSuspensionReleaseReportsOneFaultWithoutRecursion() {
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend)
        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(controller.snapshot().heldButtons, [.left])

        let faults = InputFaultRecorder()
        controller.onFault = { [weak controller] fault in
            faults.append(fault)
            // Production's callback synchronously enters the producer safety
            // fence, which calls releaseAllInputs() again.
            controller?.releaseAllInputs()
        }
        backend.configure(postResult: false)

        controller.suspendForTrackingUnavailable()

        XCTAssertEqual(faults.values, [.eventConstructionFailed])
        let snapshot = controller.snapshot()
        XCTAssertFalse(snapshot.outputEnabled)
        XCTAssertEqual(snapshot.heldButtons, [])
        XCTAssertEqual(snapshot.possiblyHeldButtons, [.left])
    }

    func testExactClickDoubleClickRightClickAndDragSequences() {
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend)

        controller.handle(.leftClick)
        controller.handle(.doubleClick)
        controller.handle(.rightClick)
        controller.handle(.dragStart)
        controller.handle(.dragStart)
        controller.handle(.dragDelta(dx: 2, dy: 3))
        drain(controller)
        controller.handle(.dragEnd)
        controller.handle(.dragEnd)

        XCTAssertEqual(backend.events(), [
            .mouse(kind: .leftDown, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftUp, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftDown, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftUp, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftDown, position: Point2D(x: 100, y: 100), button: .left, clickState: 2),
            .mouse(kind: .leftUp, position: Point2D(x: 100, y: 100), button: .left, clickState: 2),
            .mouse(kind: .rightDown, position: Point2D(x: 100, y: 100), button: .right, clickState: 1),
            .mouse(kind: .rightUp, position: Point2D(x: 100, y: 100), button: .right, clickState: 1),
            .mouse(kind: .leftDown, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftDragged, position: Point2D(x: 102, y: 103), button: .left, clickState: 1),
            .mouse(kind: .leftUp, position: Point2D(x: 100, y: 100), button: .left, clickState: 1)
        ])
        XCTAssertEqual(controller.snapshot().heldButtons, [])
        XCTAssertEqual(controller.generatedEventMarker, backend.marker)
        XCTAssertEqual(backend.batches().map(\.count), [2, 4, 2, 1, 1, 1])
    }

    func testReleaseAllInputsIsIdempotentAndRecoveryFlushPrecedesEnable() {
        let backend = FakeInputBackend()
        let trust = FakeInputTrustProvider()
        let controller = makeEnabledController(backend: backend, trust: trust)

        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(controller.snapshot().heldButtons, [.left])

        trust.isAccessibilityTrusted = false
        trust.canPostEvents = false
        controller.releaseAllInputs()
        controller.releaseAllInputs()
        XCTAssertEqual(backend.events().count, 1)
        XCTAssertEqual(controller.snapshot().heldButtons, [])
        XCTAssertEqual(controller.snapshot().possiblyHeldButtons, [.left])

        trust.isAccessibilityTrusted = true
        trust.canPostEvents = true
        controller.setOutputGate(enabled: true)
        drain(controller)
        XCTAssertTrue(controller.isOutputEnabled)
        XCTAssertEqual(backend.events(), [
            .mouse(kind: .leftDown, position: Point2D(x: 100, y: 100), button: .left, clickState: 1),
            .mouse(kind: .leftUp, position: Point2D(x: 100, y: 100), button: .left, clickState: 1)
        ])
        XCTAssertEqual(controller.snapshot().possiblyHeldButtons, [])

        controller.releaseAllInputs()
        controller.releaseAllInputs()
        XCTAssertEqual(backend.events().count, 2)
    }

    func testPhysicalButtonsSuppressClickAndDragStart() {
        let backend = FakeInputBackend()
        backend.configure(physicalButtons: [.left])
        let controller = makeEnabledController(backend: backend)

        controller.handle(.leftClick)
        controller.handle(.doubleClick)
        controller.handle(.rightClick)
        controller.handle(.dragStart)
        drain(controller)

        XCTAssertEqual(backend.events(), [])
        XCTAssertEqual(controller.snapshot().heldButtons, [])
    }

    func testPhysicalModifiersSuppressClickStartsButNeverCleanupRelease() {
        let backend = FakeInputBackend()
        let controller = makeEnabledController(backend: backend)
        backend.configure(modifiers: [.command])

        controller.handle(.leftClick)
        controller.handle(.doubleClick)
        controller.handle(.rightClick)
        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        backend.configure(modifiers: [])
        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(controller.snapshot().heldButtons, [.left])

        // Cleanup is unconditional even if a real modifier becomes held after
        // Signal pressed the mouse button.
        backend.configure(modifiers: [.command])
        controller.handle(.dragEnd)
        XCTAssertEqual(controller.snapshot().heldButtons, [])
        let mouseKinds: [InputMouseEventKind] = backend.events().compactMap { event in
            if case let .mouse(kind, _, _, _) = event { return kind }
            return nil
        }
        XCTAssertEqual(mouseKinds, [.leftDown, .leftUp])
    }

    func testCGEventModifierPolicyClearsMouseAndScrollFlags() throws {
        let allModifiers: CGEventFlags = [
            .maskCommand, .maskShift, .maskAlternate, .maskControl
        ]
        let mouse = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        mouse.flags = allModifiers
        CGInputEventBackend.applyModifierPolicy(
            to: mouse,
            for: .mouse(
                kind: .leftDown,
                position: .zero,
                button: .left,
                clickState: 1
            )
        )
        XCTAssertTrue(mouse.flags.intersection(allModifiers).isEmpty)

        let scroll = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 1,
            wheel3: 0
        ))
        scroll.flags = allModifiers
        CGInputEventBackend.applyModifierPolicy(to: scroll, for: .scroll(dx: 1, dy: 1))
        XCTAssertTrue(scroll.flags.intersection(allModifiers).isEmpty)

        let key = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 24,
            keyDown: true
        ))
        CGInputEventBackend.applyModifierPolicy(
            to: key,
            for: .key(keyCode: 24, isDown: true, modifiers: [.command, .shift])
        )
        let expectedKeyFlags: CGEventFlags = [.maskCommand, .maskShift]
        XCTAssertEqual(key.flags.intersection(allModifiers), expectedKeyFlags)

        // Exercise the production construction path with its real private
        // source. The zoom chord must end neutral and the following click must
        // be built as ordinary, unmodified mouse input.
        let backend = CGInputEventBackend(marker: 42)
        let click: [LowLevelInputEvent] = [
            .mouse(kind: .leftDown, position: .zero, button: .left, clickState: 1),
            .mouse(kind: .leftUp, position: .zero, button: .left, clickState: 1)
        ]
        let inputs = ZoomApplicationProfile.standard.zoomIn.eventPair + click
        let constructed = try XCTUnwrap(backend.constructEvents(inputs))
        XCTAssertEqual(constructed.count, inputs.count)
        XCTAssertTrue(constructed.suffix(2).allSatisfy {
            $0.flags.intersection(allModifiers).isEmpty
        })
        XCTAssertEqual(
            constructed[constructed.count - 3].flags.intersection(allModifiers),
            []
        )
        XCTAssertTrue(constructed.allSatisfy {
            $0.getIntegerValueField(.eventSourceUserData) == backend.marker
        })
    }

    func testNilCursorAndUnhealthyBackendFailClosed() {
        let cursorBackend = FakeInputBackend()
        let cursorController = makeEnabledController(backend: cursorBackend)
        cursorBackend.setCursorResult(nil)
        cursorController.handle(.pointerDelta(dx: 1, dy: 1))
        drain(cursorController)
        XCTAssertFalse(cursorController.isOutputEnabled)
        XCTAssertEqual(cursorBackend.events(), [])

        let unhealthyBackend = FakeInputBackend()
        let unhealthyController = makeEnabledController(backend: unhealthyBackend)
        unhealthyBackend.configure(healthy: false)
        unhealthyController.handle(.leftClick)
        drain(unhealthyController)
        XCTAssertFalse(unhealthyController.isOutputEnabled)
        XCTAssertEqual(unhealthyBackend.events(), [])
    }

    func testRelativeMovementProjectsToActualDisplayRectanglesNotEnvelope() {
        let backend = FakeInputBackend()
        backend.configure(displays: [
            InputDisplay(id: 1, minX: -1_280, minY: 100, maxX: 0, maxY: 900),
            InputDisplay(id: 2, minX: 0, minY: 0, maxX: 1_000, maxY: 800),
            InputDisplay(id: 3, minX: 1_000, minY: 300, maxX: 1_600, maxY: 800)
        ])
        var tuning = GestureTuning.safeDefaults
        tuning.pointerMaximumDelta = 1_000
        let controller = makeEnabledController(backend: backend, tuning: tuning)

        backend.configure(cursor: Point2D(x: 900, y: 100))
        controller.handle(.pointerDelta(dx: 200, dy: 0))
        drain(controller)

        backend.configure(cursor: Point2D(x: -1_200, y: 50))
        controller.handle(.pointerDelta(dx: -200, dy: 0))
        drain(controller)

        backend.configure(cursor: Point2D(x: 1_100, y: 500))
        controller.handle(.pointerDelta(dx: 100, dy: 0))
        drain(controller)

        XCTAssertEqual(backend.events(), [
            .mouse(
                kind: .moved,
                position: Point2D(x: Double(1_000).nextDown, y: 100),
                button: .left,
                clickState: 0
            ),
            .mouse(
                kind: .moved,
                position: Point2D(x: -1_280, y: 100),
                button: .left,
                clickState: 0
            ),
            .mouse(
                kind: .moved,
                position: Point2D(x: 1_200, y: 500),
                button: .left,
                clickState: 0
            )
        ])
    }

    func testPixelScrollAccumulatesFractionsAndNaturalDirectionOnce() {
        var directTuning = GestureTuning.safeDefaults
        directTuning.naturalScrolling = false
        let directBackend = FakeInputBackend()
        let direct = makeEnabledController(backend: directBackend, tuning: directTuning)
        direct.handle(.scroll(dx: 0.4, dy: -0.4))
        direct.handle(.scroll(dx: 0.7, dy: -0.7))
        drain(direct)
        XCTAssertEqual(directBackend.events(), [.scroll(dx: 1, dy: -1)])

        var naturalTuning = directTuning
        naturalTuning.naturalScrolling = true
        let naturalBackend = FakeInputBackend()
        let natural = makeEnabledController(backend: naturalBackend, tuning: naturalTuning)
        natural.handle(.scroll(dx: 2, dy: -3))
        drain(natural)
        XCTAssertEqual(naturalBackend.events(), [.scroll(dx: -2, dy: 3)])
    }

    func testZoomAccumulatesStepsRateLimitsAndUsesCompletePairs() {
        let backend = FakeInputBackend()
        let app = FakeFrontmostApplicationProvider("com.apple.Safari")
        let clock = FakeInputClock()
        var tuning = GestureTuning.safeDefaults
        tuning.zoomStepThreshold = 0.25
        tuning.zoomMaximumStepsPerFrame = 2
        let controller = makeEnabledController(
            backend: backend,
            application: app,
            clock: clock,
            tuning: tuning
        )

        controller.handle(.zoom(delta: 0))
        controller.handle(.zoom(delta: 0.24))
        drain(controller)
        XCTAssertEqual(backend.events(), [])

        clock.now = 0.050
        controller.handle(.zoom(delta: 0.02))
        drain(controller)
        let zoomIn = ZoomApplicationProfile.standard.zoomIn.eventPair
        XCTAssertEqual(backend.events(), zoomIn)

        clock.now = 0.060
        controller.handle(.zoom(delta: 0.25))
        drain(controller)
        XCTAssertEqual(backend.events().count, zoomIn.count)

        clock.now = 0.100
        controller.handle(.zoom(delta: 0))
        drain(controller)
        XCTAssertEqual(Array(backend.events().suffix(zoomIn.count)), zoomIn)

        backend.configure(modifiers: [.option])
        clock.now = 0.200
        controller.handle(.zoom(delta: -1))
        drain(controller)
        XCTAssertEqual(backend.events().count, zoomIn.count * 2)
    }

    func testStandardZoomUsesConfiguredAccessibilityChordsAndNoReset() {
        let profile = ZoomApplicationProfile.standard
        XCTAssertEqual(
            profile.zoomIn,
            ZoomShortcut(keyCode: 24, modifiers: [.command, .option])
        )
        XCTAssertEqual(
            profile.zoomOut,
            ZoomShortcut(keyCode: 27, modifiers: [.command, .option])
        )
        XCTAssertNil(profile.reset)

        for shortcut in [profile.zoomIn, profile.zoomOut] {
            XCTAssertTrue(shortcut.modifiers.contains(.command))
            XCTAssertTrue(shortcut.modifiers.contains(.option))
            XCTAssertFalse(shortcut.modifiers.contains(.control))
            XCTAssertFalse(shortcut.modifiers.contains(.shift))
        }

        let blockedBackend = FakeInputBackend()
        let blocked = MacOSInputController(
            backend: blockedBackend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock(),
            screenZoomShortcutsEnabled: false
        )
        enable(blocked)
        blocked.handle(.zoom(delta: GestureTuning.safeDefaults.zoomStepThreshold))
        drain(blocked)
        XCTAssertEqual(blockedBackend.events(), [])
    }

    func testFirstZoomDeltaEmitsCompleteChordThenPlainClick() {
        let backend = FakeInputBackend()
        var tuning = GestureTuning.safeDefaults
        tuning.zoomStepThreshold = 0.06
        let controller = makeEnabledController(backend: backend, tuning: tuning)

        controller.handle(.zoom(delta: 0.07))
        drain(controller)
        controller.handle(.leftClick)
        drain(controller)

        let click: [LowLevelInputEvent] = [
            .mouse(
                kind: .leftDown,
                position: Point2D(x: 100, y: 100),
                button: .left,
                clickState: 1
            ),
            .mouse(
                kind: .leftUp,
                position: Point2D(x: 100, y: 100),
                button: .left,
                clickState: 1
            )
        ]
        let zoomIn = ZoomApplicationProfile.standard.zoomIn.eventPair
        XCTAssertEqual(backend.events(), zoomIn + click)
        guard case let .key(_, false, finalFlags)? = zoomIn.last else {
            return XCTFail("Expected a final modifier release")
        }
        XCTAssertTrue(finalFlags.isEmpty)
    }

    func testZoomUserOverrideAndOptionalCommandZeroReset() {
        let backend = FakeInputBackend()
        let app = FakeFrontmostApplicationProvider("com.example.Reader")
        let clock = FakeInputClock()
        var tuning = GestureTuning.safeDefaults
        tuning.zoomStepThreshold = 0.10
        let profile = ZoomApplicationProfile(
            zoomIn: ZoomShortcut(keyCode: 42, modifiers: [.control]),
            zoomOut: ZoomShortcut(keyCode: 43, modifiers: [.option]),
            reset: ZoomShortcut(keyCode: 44, modifiers: [.command])
        )
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: app,
            clock: clock,
            tuning: tuning,
            userZoomProfiles: ["com.example.Reader": profile],
            screenZoomShortcutsEnabled: true
        )
        enable(controller)

        controller.handle(.zoom(delta: 0))
        clock.now = 0.050
        controller.handle(.zoom(delta: 0.11))
        drain(controller)
        controller.resetZoomForFrontmostApplication()
        drain(controller)

        XCTAssertEqual(
            backend.events(),
            ZoomShortcut(keyCode: 42, modifiers: [.control]).eventPair
                + ZoomShortcut(keyCode: 44, modifiers: [.command]).eventPair
        )
    }

    /// Camera coordinates are top-left based. The gesture layer preserves that
    /// semantic direction and the input boundary applies the single macOS
    /// natural-scroll inversion: hand up posts wheel-up, hand down wheel-down.
    func testPinchScrollDirectionAcrossGestureAndInput() {
        var tuning = gestureTestTuning()
        tuning.naturalScrolling = true
        // Direction is the contract under test; bypass the separately tested
        // post-close anchor-settling frames so the first displacement activates.
        tuning.scrollStabilizationFrames = 0
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        func scrollEvents(verticalDisplacement: Double) -> [GestureEvent] {
            let engine = GestureEngine(tuning: tuning)
            _ = engine.process(trackingFrame(time: 0, hands: [open.tracked(at: 0)]))
            _ = engine.process(trackingFrame(time: 0.07, hands: [open.tracked(at: 0.07)]))
            _ = engine.process(trackingFrame(time: 0.10, hands: [closed.tracked(at: 0.10)]))
            return engine.process(trackingFrame(
                time: 0.14,
                hands: [closed.translatedLocal(dx: 0, dy: verticalDisplacement).tracked(at: 0.14)]
            )).events
        }

        // Stay clearly beyond both gesture activation and the input layer's
        // integral wheel-unit boundary.
        let upward = scrollEvents(verticalDisplacement: -0.10)
        let downward = scrollEvents(verticalDisplacement: 0.10)
        guard case let .scroll(upwardDX, upwardDY)? = upward.first,
              case let .scroll(downwardDX, downwardDY)? = downward.first else {
            return XCTFail("Expected pinch-scroll events, got up=\(upward), down=\(downward)")
        }
        XCTAssertEqual(upward.count, 1)
        XCTAssertEqual(downward.count, 1)
        XCTAssertEqual(upwardDX, 0)
        XCTAssertEqual(downwardDX, 0)
        XCTAssertLessThan(upwardDY, 0)
        XCTAssertGreaterThan(downwardDY, 0)

        let upwardBackend = FakeInputBackend()
        let upwardController = makeEnabledController(backend: upwardBackend, tuning: tuning)
        upward.forEach(upwardController.handle)
        drain(upwardController)

        let downwardBackend = FakeInputBackend()
        let downwardController = makeEnabledController(backend: downwardBackend, tuning: tuning)
        downward.forEach(downwardController.handle)
        drain(downwardController)

        let expectedUp = Int32((-upwardDY).rounded(.towardZero))
        let expectedDown = Int32((-downwardDY).rounded(.towardZero))
        XCTAssertGreaterThan(expectedUp, 0)
        XCTAssertLessThan(expectedDown, 0)
        XCTAssertEqual(upwardBackend.events(), [.scroll(dx: 0, dy: expectedUp)])
        XCTAssertEqual(downwardBackend.events(), [.scroll(dx: 0, dy: expectedDown)])
    }

    func testProductionDefaultsProduceRepeatedScrollAndReachZoomOnShortMotion() {
        let open = SyntheticHand.pose(.pinch(ratio: 0.45))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))

        func prime(_ pipeline: GesturePipeline) {
            _ = pipeline.process(trackingFrame(time: 0, hands: [open.tracked(at: 0)]))
            _ = pipeline.process(trackingFrame(time: 0.07, hands: [open.tracked(at: 0.07)]))
            _ = pipeline.process(trackingFrame(time: 0.10, hands: [closed.tracked(at: 0.10)]))
            _ = pipeline.process(trackingFrame(time: 0.12, hands: [closed.tracked(at: 0.12)]))
        }

        let scrollBackend = FakeInputBackend()
        let scrollController = makeEnabledController(backend: scrollBackend)
        let scrollPipeline = GesturePipeline(tuning: .safeDefaults, inputSink: scrollController)
        prime(scrollPipeline)
        _ = scrollPipeline.process(trackingFrame(
            time: 0.14,
            hands: [closed.translatedLocal(dx: 0, dy: 0.05).tracked(at: 0.14)]
        ))
        _ = scrollPipeline.process(trackingFrame(
            time: 0.16,
            hands: [closed.translatedLocal(dx: 0, dy: 0.07).tracked(at: 0.16)]
        ))
        drain(scrollController)
        XCTAssertEqual(scrollBackend.events(), [
            .scroll(dx: 0, dy: -1),
            .scroll(dx: 0, dy: -2)
        ])

        let zoomBackend = FakeInputBackend()
        let zoomController = makeEnabledController(backend: zoomBackend)
        let zoomPipeline = GesturePipeline(tuning: .safeDefaults, inputSink: zoomController)
        prime(zoomPipeline)
        _ = zoomPipeline.process(trackingFrame(
            time: 0.14,
            hands: [closed.translatedLocal(dx: 0.05, dy: 0).tracked(at: 0.14)]
        ))
        _ = zoomPipeline.process(trackingFrame(
            time: 0.16,
            hands: [closed.translatedLocal(dx: 0.07, dy: 0).tracked(at: 0.16)]
        ))
        drain(zoomController)
        XCTAssertEqual(
            zoomBackend.events(),
            ZoomApplicationProfile.standard.zoomIn.eventPair
        )
    }

    private func makeController(
        backend: FakeInputBackend,
        trust: FakeInputTrustProvider = FakeInputTrustProvider(),
        application: FakeFrontmostApplicationProvider = FakeFrontmostApplicationProvider(),
        clock: FakeInputClock = FakeInputClock(),
        tuning: GestureTuning = .safeDefaults
    ) -> MacOSInputController {
        MacOSInputController(
            backend: backend,
            trustProvider: trust,
            applicationProvider: application,
            clock: clock,
            tuning: tuning,
            screenZoomShortcutsEnabled: true
        )
    }

    private func makeEnabledController(
        backend: FakeInputBackend,
        trust: FakeInputTrustProvider = FakeInputTrustProvider(),
        application: FakeFrontmostApplicationProvider = FakeFrontmostApplicationProvider(),
        clock: FakeInputClock = FakeInputClock(),
        tuning: GestureTuning = .safeDefaults
    ) -> MacOSInputController {
        let controller = makeController(
            backend: backend,
            trust: trust,
            application: application,
            clock: clock,
            tuning: tuning
        )
        enable(controller)
        return controller
    }

    private func enable(_ controller: MacOSInputController) {
        controller.setOutputGate(enabled: true)
        drain(controller)
        XCTAssertTrue(controller.isOutputEnabled)
    }

    private func drain(_ controller: MacOSInputController) {
        _ = controller.snapshot()
        _ = controller.snapshot()
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return condition()
    }
}

private enum PipelineAction: Equatable {
    case clutch
    case suspend
    case event(GestureEvent)
}

private final class PipelineClutchSpy: TransientOutputClutching, TrackingOutputSuspending {
    private(set) var actions: [PipelineAction] = []

    func handle(_ event: GestureEvent) {
        actions.append(.event(event))
    }

    func releaseAllInputs() {}

    func clutchPendingNormalOutput() {
        actions.append(.clutch)
    }

    func suspendForTrackingUnavailable() {
        actions.append(.suspend)
    }

    func clear() {
        actions.removeAll(keepingCapacity: true)
    }
}

private final class ClutchBlockingInputBackend: InputEventBackend, @unchecked Sendable {
    let marker: Int64 = 0x434C555443485445

    private let condition = NSCondition()
    private var shouldBlockHealthCheck = false
    private var healthCheckIsBlocked = false
    private var shouldBlockCursorRead = false
    private var cursorReadIsBlocked = false
    private var storedEvents: [LowLevelInputEvent] = []

    var isHealthy: Bool {
        condition.lock()
        healthCheckIsBlocked = shouldBlockHealthCheck
        condition.broadcast()
        while shouldBlockHealthCheck {
            condition.wait()
        }
        healthCheckIsBlocked = false
        condition.unlock()
        return true
    }

    func currentCursorLocation() -> Point2D? {
        condition.lock()
        cursorReadIsBlocked = shouldBlockCursorRead
        condition.broadcast()
        while shouldBlockCursorRead {
            condition.wait()
        }
        cursorReadIsBlocked = false
        condition.unlock()
        return Point2D(x: 100, y: 100)
    }

    func activeDisplays() -> [InputDisplay] {
        [InputDisplay(id: 1, minX: 0, minY: 0, maxX: 1_000, maxY: 800)]
    }

    func isPhysicalButtonPressed(_: InputMouseButton) -> Bool { false }
    func physicalModifierFlags() -> InputModifierFlags { [] }

    func post(_ events: [LowLevelInputEvent]) -> Bool {
        condition.lock()
        storedEvents.append(contentsOf: events)
        condition.unlock()
        return true
    }

    func events() -> [LowLevelInputEvent] {
        condition.lock()
        defer { condition.unlock() }
        return storedEvents
    }

    func blockHealthCheck() {
        condition.lock()
        shouldBlockHealthCheck = true
        healthCheckIsBlocked = false
        condition.unlock()
    }

    func waitUntilHealthCheckIsBlocked(timeout: TimeInterval = 1) -> Bool {
        waitUntil(timeout: timeout) { healthCheckIsBlocked }
    }

    func resumeHealthCheck() {
        condition.lock()
        shouldBlockHealthCheck = false
        condition.broadcast()
        condition.unlock()
    }

    func blockCursorRead() {
        condition.lock()
        shouldBlockCursorRead = true
        cursorReadIsBlocked = false
        condition.unlock()
    }

    func waitUntilCursorReadIsBlocked(timeout: TimeInterval = 1) -> Bool {
        waitUntil(timeout: timeout) { cursorReadIsBlocked }
    }

    func resumeCursorRead() {
        condition.lock()
        shouldBlockCursorRead = false
        condition.broadcast()
        condition.unlock()
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ predicate: () -> Bool
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while !predicate() {
            if !condition.wait(until: deadline) { return predicate() }
        }
        return true
    }
}

private final class InputFaultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [InputControllerFault] = []

    func append(_ fault: InputControllerFault) {
        lock.lock()
        stored.append(fault)
        lock.unlock()
    }

    var values: [InputControllerFault] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
