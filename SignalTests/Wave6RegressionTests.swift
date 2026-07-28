import Foundation
import XCTest
@testable import Signal

final class Wave6RegressionTests: XCTestCase {
    func testCameraFrameFreshnessGateLearnsClockOffsetAndResetsPerGeneration() {
        var gate = CameraFrameFreshnessGate()

        XCTAssertTrue(gate.accepts(nil))
        XCTAssertTrue(gate.accepts(0.070))
        XCTAssertEqual(gate.minimumObservedAgeSeconds, 0.070)
        XCTAssertTrue(gate.accepts(0.100))
        XCTAssertFalse(gate.accepts(0.137))
        XCTAssertFalse(gate.accepts(0.151))

        XCTAssertTrue(gate.accepts(0.040))
        XCTAssertEqual(gate.minimumObservedAgeSeconds, 0.040)
        XCTAssertFalse(gate.accepts(0.107))

        gate.reset()
        XCTAssertNil(gate.minimumObservedAgeSeconds)
        XCTAssertTrue(gate.accepts(0.137))
        XCTAssertEqual(gate.minimumObservedAgeSeconds, 0.137)

        XCTAssertFalse(gate.accepts(-0.001))
        XCTAssertFalse(gate.accepts(.nan))
        XCTAssertFalse(gate.accepts(.infinity))
    }

    func testNoFrameWatchdogClampsToHard150MillisecondsAndFiresOnce() {
        let clock = LockedTestClock(10)
        let callbacks = WatchdogCallbackRecorder()
        let watchdog = TrackingLossWatchdog(now: { clock.value }) { timestamp, generation in
            callbacks.append(timestamp, generation)
        }
        watchdog.arm(
            snapshot: TrackingSnapshot(
                captureGeneration: 7,
                timestamp: MonotonicTimestamp(rawValue: 4),
                hands: [],
                quality: .good
            ),
            grace: 0.5
        )

        XCTAssertFalse(watchdog.check(now: 10.1499))
        XCTAssertTrue(watchdog.check(now: 10.15))
        XCTAssertFalse(watchdog.check(now: 11))
        let values = callbacks.values
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].0.rawValue, 4.15, accuracy: 1e-9)
        XCTAssertEqual(values[0].1, 7)
        watchdog.disarm()
    }

    func testFreshNoHandSnapshotRearmsNoFrameWatchdog() {
        let clock = LockedTestClock(10)
        let callbacks = WatchdogCallbackRecorder()
        let watchdog = TrackingLossWatchdog(now: { clock.value }) { timestamp, generation in
            callbacks.append(timestamp, generation)
        }
        watchdog.arm(
            snapshot: TrackingSnapshot(
                captureGeneration: 7,
                timestamp: .init(rawValue: 4),
                hands: [SyntheticHand.pose(.pointer).tracked(at: 4)],
                quality: .good
            ),
            grace: 0.15
        )
        clock.set(10.10)
        watchdog.arm(
            snapshot: TrackingSnapshot(
                captureGeneration: 7,
                timestamp: .init(rawValue: 4.10),
                hands: [],
                quality: .absent,
                degradationReason: .noHandDetected
            ),
            grace: 0.15
        )

        XCTAssertFalse(watchdog.check(now: 10.15))
        XCTAssertTrue(watchdog.check(now: 10.25))
        XCTAssertEqual(callbacks.values.count, 1)
        XCTAssertEqual(callbacks.values[0].0.rawValue, 4.25, accuracy: 1e-9)
    }

    func testStartupWatchdogFiresWhenNoFirstSnapshotArrives() {
        let clock = LockedTestClock(20)
        let callbacks = WatchdogCallbackRecorder()
        let watchdog = TrackingLossWatchdog(now: { clock.value }) { timestamp, generation in
            callbacks.append(timestamp, generation)
        }
        watchdog.armWaitingForFirstSnapshot(captureGeneration: 19)

        XCTAssertFalse(watchdog.check(now: 21.9999))
        XCTAssertTrue(watchdog.check(now: 22.0000))
        XCTAssertEqual(callbacks.values.count, 1)
        XCTAssertEqual(callbacks.values[0].0.rawValue, 22.0, accuracy: 1e-9)
        XCTAssertEqual(callbacks.values[0].1, 19)
    }

    func testDelayedFirstSnapshotSwitchesStartupWatchdogToSteadyState() {
        let clock = LockedTestClock(30)
        let callbacks = WatchdogCallbackRecorder()
        let watchdog = TrackingLossWatchdog(now: { clock.value }) { timestamp, generation in
            callbacks.append(timestamp, generation)
        }
        watchdog.armWaitingForFirstSnapshot(captureGeneration: 23)

        XCTAssertFalse(watchdog.check(now: 31.5))
        clock.set(31.5)
        watchdog.arm(
            snapshot: TrackingSnapshot(
                captureGeneration: 23,
                timestamp: .init(rawValue: 8.5),
                hands: [],
                quality: .absent,
                degradationReason: .noHandDetected
            ),
            grace: 0.15
        )
        XCTAssertEqual(callbacks.values.count, 0)
        XCTAssertFalse(watchdog.check(now: 31.6499))
        XCTAssertTrue(watchdog.check(now: 31.6500))
        XCTAssertEqual(callbacks.values.count, 1)
        XCTAssertEqual(callbacks.values[0].0.rawValue, 8.65, accuracy: 1e-9)
    }

    func testDegradedSnapshotCannotEmitNormalGestureOutput() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let pointer = SyntheticHand.pose(.pointer)
        _ = engine.process(trackingFrame(time: 0, hands: [pointer.tracked(at: 0)]))
        _ = engine.process(trackingFrame(time: 0.14, hands: [pointer.tracked(at: 0.14)]))
        let degraded = trackingFrame(
            time: 0.16,
            hands: [pointer.translatedLocal(dx: 0.04, dy: 0).tracked(at: 0.16)],
            quality: .degraded
        )
        XCTAssertEqual(engine.process(degraded).events, [])
    }

    func testCaptureGenerationIsRevalidatedAtInputBoundary() {
        let backend = FakeInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )
        controller.captureGenerationValidator = { $0 == 8 }
        controller.setOutputGate(enabled: true)
        drain(controller)

        controller.handle(.leftClick, captureGeneration: 7)
        drain(controller)
        XCTAssertEqual(backend.batches(), [])

        controller.handle(.leftClick, captureGeneration: 8)
        drain(controller)
        XCTAssertEqual(backend.batches().count, 1)
        XCTAssertEqual(backend.batches().first?.count, 2)
    }

    func testReplacingPendingClickOwnerCancelsWithoutLegacyCleanup() {
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        let engine = GestureEngine(tuning: gestureTestTuning())
        _ = events(engine, open, at: 0)
        _ = events(engine, open, at: 0.07)
        _ = events(engine, closed, at: 0.10)
        let replacement = closed.tracked(id: 99, at: 0.12)
        XCTAssertEqual(engine.process(trackingFrame(time: 0.12, hands: [replacement])).events, [])
        XCTAssertEqual(engine.reset(reason: .disabled), [])
    }

    func testExtremeZoomValuesAreBoundedAndNonTrapping() {
        let bundleIdentifier = "com.example.AllModifiers"
        let allModifiers: InputModifierFlags = [.control, .option, .shift, .command]
        let shortcut = ZoomShortcut(keyCode: 42, modifiers: allModifiers)
        let controller = ZoomController(
            applicationProvider: FakeFrontmostApplicationProvider(bundleIdentifier),
            clock: FakeInputClock(now: 1),
            userProfiles: [
                bundleIdentifier: ZoomApplicationProfile(
                    zoomIn: shortcut,
                    zoomOut: shortcut
                )
            ]
        )
        var tuning = GestureTuning.safeDefaults
        tuning.zoomStepThreshold = Double.leastNormalMagnitude
        tuning.zoomMaximumStepsPerFrame = .max
        _ = controller.events(for: 0, tuning: tuning, physicalModifiers: [])
        let events = controller.events(
            for: Double.greatestFiniteMagnitude,
            tuning: tuning,
            physicalModifiers: []
        )
        let expected = (0..<8).flatMap { _ in shortcut.eventPair }
        XCTAssertEqual(events, expected)
        XCTAssertEqual(events.count, 80)
        XCTAssertEqual(events.filter {
            guard case let .key(keyCode, isDown, modifiers) = $0 else { return false }
            return keyCode == 42 && isDown && modifiers == allModifiers
        }.count, 8)
        XCTAssertEqual(events.filter {
            guard case let .key(keyCode, isDown, modifiers) = $0 else { return false }
            return keyCode == 42 && !isDown && modifiers == allModifiers
        }.count, 8)
        guard case let .key(_, false, finalFlags)? = events.last else {
            return XCTFail("Expected a final modifier release")
        }
        XCTAssertTrue(finalFlags.isEmpty)
    }

    func testGestureDiagnosticsSafeDefaultAndTrackingReasonRoundTrip() throws {
        XCTAssertEqual(GestureDiagnostics.safeDefault.activeGesture, .rest)
        XCTAssertFalse(GestureDiagnostics.safeDefault.pendingClick)
        let snapshot = TrackingSnapshot(
            timestamp: .init(rawValue: 1),
            hands: [],
            quality: .degraded,
            degradationReason: .staleFrame
        )
        let decoded = try JSONDecoder().decode(
            TrackingSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.degradationReason, .staleFrame)
    }

    func testAspectFillProjectionMatchesHorizontalCrop() {
        let projection = AspectFillProjection(sourceAspectRatio: 4.0 / 3.0)
        let center = projection.project(Point2D(x: 0.5, y: 0.5), into: CGSize(width: 400, height: 400))
        let left = projection.project(Point2D(x: 0, y: 0.5), into: CGSize(width: 400, height: 400))
        XCTAssertEqual(center.x, 200, accuracy: 1e-9)
        XCTAssertEqual(center.y, 200, accuracy: 1e-9)
        XCTAssertLessThan(left.x, 0)
    }

    @MainActor
    func testLatestOnlyDeliveryDropsInvalidatedEpoch() async {
        let delivery = LatestOnlyMainActorDelivery<Int>()
        let recorder = MainActorIntRecorder()
        delivery.submit(1) { recorder.append($0) }
        delivery.invalidate()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(recorder.values, [])

        delivery.submit(2) { recorder.append($0) }
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(recorder.values, [2])
    }

    @MainActor
    func testTerminalDeliveryCannotBeCoalescedAwayByLaterSnapshot() async {
        let delivery = LatestOnlyMainActorDelivery<Int>()
        let recorder = MainActorIntRecorder()
        delivery.submit(1) { recorder.append($0) }
        delivery.submitUncoalesced(2) { recorder.append($0) }
        delivery.submit(3) { recorder.append($0) }

        for _ in 0..<6 { await Task.yield() }

        XCTAssertTrue(recorder.values.contains(2))
        XCTAssertEqual(recorder.values.filter { $0 == 2 }.count, 1)
        XCTAssertFalse(recorder.values.contains(1))
    }

    @MainActor
    func testDequeuedDeliveryCannotReenableAfterEveryProducerSafetyFence() async {
        for source in ProducerSafetySource.allCases {
            let backend = FakeInputBackend()
            let controller = MacOSInputController(
                backend: backend,
                trustProvider: FakeInputTrustProvider(),
                applicationProvider: FakeFrontmostApplicationProvider(),
                clock: FakeInputClock()
            )
            let lease = SafetyEnableLease()
            let token = lease.issue()
            let latch = BlockingPublicationLatch()
            let delivery = LatestOnlyMainActorDelivery<Int>(dequeueHook: { latch.pause() })
            let fence = ProducerSafetyFence(
                lease: lease,
                invalidateDeliveries: { delivery.invalidate() },
                releaseInput: { [weak controller] in controller?.releaseAllInputs() }
            )
            let watchdogResult = LockedBoolean(false)
            let safetyTask = Task.detached {
                latch.waitUntilPaused()
                if source == .watchdog {
                    let clock = LockedTestClock(50)
                    let watchdog = TrackingLossWatchdog(now: { clock.value }) { _, _ in
                        fence.revoke(for: .watchdog)
                    }
                    watchdog.arm(
                        snapshot: TrackingSnapshot(
                            captureGeneration: 44,
                            timestamp: MonotonicTimestamp(rawValue: 7),
                            hands: [],
                            quality: .good
                        ),
                        grace: 0.1
                    )
                    watchdogResult.set(watchdog.check(now: 50.1))
                    watchdog.disarm()
                } else {
                    fence.revoke(for: source)
                }
                latch.resume()
            }

            delivery.submit(1) { _ in
                _ = lease.withValid(token) {
                    controller.setOutputGate(enabled: true)
                    _ = controller.snapshot()
                    controller.handle(.leftClick)
                    _ = controller.snapshot()
                }
            }
            await safetyTask.value

            if source == .watchdog {
                XCTAssertTrue(watchdogResult.value, "watchdog did not fire")
            }
            XCTAssertFalse(controller.isOutputEnabled, "source=\(source.rawValue)")
            XCTAssertEqual(backend.batches(), [], "source=\(source.rawValue)")
        }
    }

    func testCameraGenerationInvalidationWhileValidatorIsBlockedDropsWholeBatch() {
        let backend = FakeInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )
        controller.setOutputGate(enabled: true)
        drain(controller)
        XCTAssertTrue(controller.isOutputEnabled)

        let cameraGenerationIsCurrent = LockedBoolean(true)
        let latch = BlockingPublicationLatch()
        controller.captureGenerationValidator = { generation in
            guard generation == 17 else { return false }
            latch.pause()
            return cameraGenerationIsCurrent.value
        }
        controller.handle(.leftClick, captureGeneration: 17)
        latch.waitUntilPaused()

        cameraGenerationIsCurrent.set(false)
        controller.setOutputGate(enabled: false)
        latch.resume()
        drain(controller)

        XCTAssertFalse(controller.isOutputEnabled)
        XCTAssertEqual(backend.batches(), [])
    }

    func testStructuredOneHandZoomEpisodeEndsOnReleaseAndAccumulatorResetsByIdentity() {
        let engine = GestureEngine(tuning: gestureTestTuning())
        let open = SyntheticHand.pose(.pinch(ratio: 0.35))
        let closed = SyntheticHand.pose(.pinch(ratio: 0.20))
        for (time, hand) in [
            (0.000, open), (0.070, open), (0.100, closed),
            (0.120, closed), (0.140, closed)
        ] {
            _ = engine.process(trackingFrame(time: time, hands: [hand.tracked(at: time)]))
        }
        let active = engine.process(trackingFrame(
            time: 0.160,
            hands: [closed.translatedLocal(dx: 0.08, dy: 0).tracked(at: 0.160)]
        ))
        XCTAssertEqual(active.zoomEpisode.phase, .active)
        XCTAssertEqual(active.zoomEpisode.handIDs.map(\.rawValue), [1])

        let inactive = engine.process(trackingFrame(
            time: 0.200,
            hands: [open.translatedLocal(dx: 0.08, dy: 0).tracked(at: 0.200)]
        ))
        XCTAssertEqual(inactive.zoomEpisode, .inactive)

        var accumulator = ZoomEpisodeAccumulator()
        let first = ZoomEpisodeDiagnostic(
            phase: .active,
            handIDs: [HandTrackID(rawValue: 11)]
        )
        XCTAssertEqual(accumulator.consume(delta: 0.4, episode: first), 0.4, accuracy: 1e-9)
        XCTAssertEqual(accumulator.consume(delta: 0.2, episode: inactive.zoomEpisode), 0, accuracy: 1e-9)
        XCTAssertEqual(accumulator.consume(delta: 0.3, episode: first), 0.3, accuracy: 1e-9)
        let replacement = ZoomEpisodeDiagnostic(
            phase: .active,
            handIDs: [HandTrackID(rawValue: 33)]
        )
        XCTAssertEqual(accumulator.consume(delta: 0.1, episode: replacement), 0.1, accuracy: 1e-9)
    }

    @MainActor
    func testUnsupportedZoomKeyAndUnsafeMaximumAreRejected() throws {
        XCTAssertNil(ZoomShortcutKeyCatalog.mapping(for: "🙂"))
        var tuning = GestureTuning.safeDefaults
        tuning.zoomMaximumStepsPerFrame = 9
        XCTAssertEqual(tuning.validated(), .safeDefaults)

        let suite = "com.allenxu.SignalTests.wave6.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.upsertZoomProfile(.init(
            bundleIdentifier: "com.example.invalid",
            displayName: "Invalid",
            zoomIn: .init(keyEquivalent: "🙂"),
            zoomOut: .zoomOutDefault
        )))
    }

    private func events(_ engine: GestureEngine, _ hand: SyntheticHand, at time: Double) -> [GestureEvent] {
        engine.process(trackingFrame(time: time, hands: [hand.tracked(at: time)])).events
    }

    private func drain(_ controller: MacOSInputController) {
        _ = controller.snapshot()
        _ = controller.snapshot()
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double

    init(_ value: Double) { storedValue = value }
    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Double) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private final class WatchdogCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(MonotonicTimestamp, UInt64)] = []

    func append(_ timestamp: MonotonicTimestamp, _ generation: UInt64) {
        lock.lock()
        stored.append((timestamp, generation))
        lock.unlock()
    }

    var values: [(MonotonicTimestamp, UInt64)] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class BlockingPublicationLatch: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let mayContinue = DispatchSemaphore(value: 0)

    func pause() {
        entered.signal()
        mayContinue.wait()
    }

    func waitUntilPaused() {
        entered.wait()
    }

    func resume() {
        mayContinue.signal()
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

@MainActor
private final class MainActorIntRecorder {
    private(set) var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}
