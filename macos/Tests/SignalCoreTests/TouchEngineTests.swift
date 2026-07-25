import XCTest
@testable import SignalCore

final class TouchEngineTests: XCTestCase {
    func testPointerReanchorsAndMovesRelatively() {
        var configuration = TouchConfiguration()
        configuration.pointerSensitivity = 100
        configuration.pointerSmoothing = 0
        configuration.pointerAcceleration = 1
        configuration.pointerDeadZone = 0
        var engine = TouchEngine(configuration: configuration)

        XCTAssertEqual(engine.process(frame(0, pointer: true, center: .init(x: 0.5, y: 0.5))), [.state(.pointer)])
        let output = engine.process(frame(0.01, pointer: true, center: .init(x: 0.6, y: 0.5)))
        guard case .pointer(let delta) = output.first else {
            return XCTFail("Expected relative movement")
        }
        XCTAssertEqual(delta.x, -10, accuracy: 0.001, "Camera X is naturally mirrored")
        XCTAssertEqual(delta.y, 0, accuracy: 0.001)
    }

    func testPointerDeadZoneAndAcceleration() {
        var configuration = TouchConfiguration()
        configuration.pointerSensitivity = 100
        configuration.pointerSmoothing = 0
        configuration.pointerAcceleration = 2
        configuration.pointerDeadZone = 0.05
        var engine = TouchEngine(configuration: configuration)
        _ = engine.process(frame(0, pointer: true, center: .zero))
        XCTAssertTrue(engine.process(frame(0.01, pointer: true, center: .init(x: 0.03, y: 0))).isEmpty)
        let output = engine.process(frame(0.02, pointer: true, center: .init(x: 0.13, y: 0)))
        guard case .pointer(let delta) = output.first else { return XCTFail("Expected movement") }
        XCTAssertLessThan(abs(delta.x), 1, "Acceleration preserves small-motion precision")
    }

    func testPointerReanchorsAfterPoseExitAndTrackingGap() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pointer: true, center: .zero))
        _ = engine.process(frame(0.01, pointer: false, center: .init(x: 0.4, y: 0)))
        XCTAssertEqual(
            engine.process(frame(0.02, pointer: true, center: .init(x: 0.9, y: 0))),
            [.state(.pointer)],
            "Re-entry must not jump"
        )
        _ = engine.process(TouchFrame(timestamp: 0.03, trackingValid: false))
        XCTAssertEqual(
            engine.process(frame(0.04, pointer: true, center: .init(x: 0.1, y: 0))),
            [.state(.pointer)],
            "Tracking-gap recovery must re-anchor"
        )
    }

    func testQuickPinchProducesExactlyOneClickOnRelease() {
        var engine = TouchEngine()
        XCTAssertEqual(engine.process(frame(0, pinch: 0.2)), [.state(.pinchPending)])
        XCTAssertEqual(engine.process(frame(0.18, pinch: 0.5)), [.click, .state(.idle)])
        XCTAssertFalse(engine.process(frame(0.19, pinch: 0.5)).contains(.click))
    }

    func testSlowStationaryPinchDoesNotClickByDefault() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2))
        XCTAssertEqual(engine.process(frame(0.5, pinch: 0.5)), [.state(.idle)])
    }

    func testMovementOverClickThresholdDoesNotClick() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        let output = engine.process(frame(0.2, pinch: 0.5, center: .init(x: 0.18, y: 0.18)))
        XCTAssertFalse(output.contains(.click))
    }

    func testVerticalAxisLocksAndNeverClicks() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        XCTAssertEqual(
            engine.process(frame(0.13, pinch: 0.2, center: .init(x: 0.02, y: 0.25))),
            [.state(.verticalLocked)]
        )
        XCTAssertTrue(engine.process(frame(0.15, pinch: 0.2, center: .init(x: 0.02, y: 0.35))).contains {
            if case .scroll = $0 { return true }
            return false
        })
        XCTAssertFalse(engine.process(frame(0.2, pinch: 0.5, center: .init(x: 0.02, y: 0.35))).contains(.click))
    }

    func testHorizontalAxisLocksAndNeverClicks() {
        var configuration = TouchConfiguration()
        configuration.zoomGain = 20
        var engine = TouchEngine(configuration: configuration)
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        XCTAssertEqual(
            engine.process(frame(0.13, pinch: 0.2, center: .init(x: 0.25, y: 0.01))),
            [.state(.horizontalLocked)]
        )
        XCTAssertTrue(engine.process(frame(0.15, pinch: 0.2, center: .init(x: 0.35, y: 0.01))).contains {
            if case .zoom = $0 { return true }
            return false
        })
        XCTAssertFalse(engine.process(frame(0.2, pinch: 0.5, center: .init(x: 0.35, y: 0.01))).contains(.click))
    }

    func testAmbiguousDiagonalRemainsPending() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        XCTAssertTrue(engine.process(frame(0.15, pinch: 0.2, center: .init(x: 0.3, y: 0.3))).isEmpty)
        XCTAssertEqual(engine.state, .pinchPending)
    }

    func testAxisCannotSwitchAfterVerticalLock() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        _ = engine.process(frame(0.13, pinch: 0.2, center: .init(x: 0, y: 0.25)))
        _ = engine.process(frame(0.2, pinch: 0.2, center: .init(x: 0.7, y: 0.25)))
        XCTAssertEqual(engine.state, .verticalLocked)
    }

    func testScrollAndZoomInversion() {
        var normal = TouchConfiguration()
        normal.scrollGain = 100
        var inverted = normal
        inverted.scrollInverted = true
        let normalAmount = verticalScrollOutput(configuration: normal)
        let invertedAmount = verticalScrollOutput(configuration: inverted)
        XCTAssertEqual(normalAmount, -invertedAmount, accuracy: 0.001)

        var zoomNormal = TouchConfiguration()
        zoomNormal.zoomGain = 20
        var zoomInverted = zoomNormal
        zoomInverted.zoomInverted = true
        XCTAssertEqual(horizontalZoomOutput(configuration: zoomNormal), -horizontalZoomOutput(configuration: zoomInverted))
    }

    func testTrackingLossCancelsPinchWithoutClick() {
        var engine = TouchEngine()
        _ = engine.process(frame(0, pinch: 0.2))
        XCTAssertEqual(engine.process(TouchFrame(timestamp: 0.1, trackingValid: false)), [.state(.cancelled)])
        XCTAssertFalse(engine.process(frame(0.15, pinch: 0.5)).contains(.click))
    }

    func testStaleFrameRejectedAndLowFPSTimingUsesMonotonicTimestamp() {
        var engine = TouchEngine()
        XCTAssertTrue(engine.process(TouchFrame(
            timestamp: 0,
            frameAge: 0.8,
            trackingValid: true,
            pointerPose: true
        )).isEmpty)
        _ = engine.process(frame(10, pinch: 0.2))
        XCTAssertEqual(engine.process(frame(10.27, pinch: 0.5)), [.click, .state(.idle)])
    }

    private func verticalScrollOutput(configuration: TouchConfiguration) -> Double {
        var engine = TouchEngine(configuration: configuration)
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        _ = engine.process(frame(0.13, pinch: 0.2, center: .init(x: 0, y: 0.25)))
        for output in engine.process(frame(0.15, pinch: 0.2, center: .init(x: 0, y: 0.35))) {
            if case .scroll(let value) = output { return value }
        }
        return 0
    }

    private func horizontalZoomOutput(configuration: TouchConfiguration) -> Int {
        var engine = TouchEngine(configuration: configuration)
        _ = engine.process(frame(0, pinch: 0.2, center: .zero))
        _ = engine.process(frame(0.13, pinch: 0.2, center: .init(x: 0.25, y: 0)))
        for output in engine.process(frame(0.15, pinch: 0.2, center: .init(x: 0.35, y: 0))) {
            if case .zoom(let value) = output { return value }
        }
        return 0
    }

    private func frame(
        _ time: TimeInterval,
        pointer: Bool = false,
        pinch: Double = 1,
        center: Point2D = .zero
    ) -> TouchFrame {
        TouchFrame(
            timestamp: time,
            pointerPose: pointer,
            pinchDistance: pinch,
            handCenter: center,
            palmScale: 1
        )
    }
}
