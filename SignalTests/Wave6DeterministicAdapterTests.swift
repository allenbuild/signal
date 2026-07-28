import Foundation
import XCTest
@testable import Signal

final class Wave6DeterministicAdapterTests: XCTestCase {
    func testAssociationCrossingAmbiguityPositionScaleAndRetentionBoundaries() {
        var crossing = HandAssociator(tuning: .safeDefaults)
        var firstID: HandTrackID?
        var final: HandAssociationUpdate?
        for index in 0..<120 {
            let progress = Double(index) / 119
            let time = 10 + Double(index) / 30
            let left = SyntheticHand.pose(.pointer)
                .withChirality(.left)
                .translatedLocal(dx: -1.2 + 2.4 * progress, dy: 0)
                .rawObservation(at: time)
            let right = SyntheticHand.pose(.pointer)
                .withChirality(.right)
                .translatedLocal(dx: 1.2 - 2.4 * progress, dy: 0)
                .rawObservation(at: time)
            let observations = index.isMultiple(of: 2) ? [right, left] : [left, right]
            final = crossing.process(observations: observations, at: .init(rawValue: time))
            if index == 0 {
                firstID = final?.hands.min(by: { wristX($0) < wristX($1) })?.id
            }
        }
        let crossedHand = final?.hands.first(where: { $0.id == firstID })
        XCTAssertTrue(wristX(crossedHand) > 0.5)

        var ambiguous = HandAssociator(tuning: .safeDefaults)
        _ = ambiguous.process(
            observations: [
                SyntheticHand.pose(.pointer).translatedLocal(dx: -0.4, dy: 0).rawObservation(at: 20),
                SyntheticHand.pose(.pointer).translatedLocal(dx: 0.4, dy: 0).rawObservation(at: 20)
            ],
            at: .init(rawValue: 20)
        )
        let same = SyntheticHand.pose(.pointer).rawObservation(at: 20.033)
        let ambiguousUpdate = ambiguous.process(
            observations: [same, same],
            at: .init(rawValue: 20.033)
        )
        XCTAssertTrue(ambiguousUpdate.ambiguous)
        XCTAssertEqual(ambiguousUpdate.quality, .degraded)
        XCTAssertTrue(ambiguousUpdate.hands.allSatisfy { !$0.associationCertain })

        var gateTuning = GestureTuning.safeDefaults
        gateTuning.associationPositionGate = 1
        gateTuning.associationScaleRatioMinimum = 0.8
        gateTuning.associationScaleRatioMaximum = 1.2

        var insidePosition = HandAssociator(tuning: gateTuning)
        _ = insidePosition.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 30)],
            at: .init(rawValue: 30)
        )
        let insidePositionUpdate = insidePosition.process(
            observations: [SyntheticHand.pose(.pointer).translatedLocal(dx: 0.99, dy: 0).rawObservation(at: 30.033)],
            at: .init(rawValue: 30.033)
        )
        XCTAssertEqual(insidePositionUpdate.hands.filter { $0.missingDuration == 0 }.map(\.id), [HandTrackID(rawValue: 1)])

        var outsidePosition = HandAssociator(tuning: gateTuning)
        _ = outsidePosition.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 31)],
            at: .init(rawValue: 31)
        )
        let outsidePositionUpdate = outsidePosition.process(
            observations: [SyntheticHand.pose(.pointer).translatedLocal(dx: 1.01, dy: 0).rawObservation(at: 31.033)],
            at: .init(rawValue: 31.033)
        )
        XCTAssertEqual(outsidePositionUpdate.hands.filter { $0.missingDuration == 0 }.map(\.id), [HandTrackID(rawValue: 2)])

        var insideScale = HandAssociator(tuning: gateTuning)
        _ = insideScale.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 32)],
            at: .init(rawValue: 32)
        )
        let insideScaleUpdate = insideScale.process(
            observations: [SyntheticHand.pose(.pointer).scaledLocal(1.2).rawObservation(at: 32.033)],
            at: .init(rawValue: 32.033)
        )
        XCTAssertEqual(insideScaleUpdate.hands.filter { $0.missingDuration == 0 }.map(\.id), [HandTrackID(rawValue: 1)])

        var outsideScale = HandAssociator(tuning: gateTuning)
        _ = outsideScale.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 33)],
            at: .init(rawValue: 33)
        )
        let outsideScaleUpdate = outsideScale.process(
            observations: [SyntheticHand.pose(.pointer).scaledLocal(1.201).rawObservation(at: 33.033)],
            at: .init(rawValue: 33.033)
        )
        XCTAssertEqual(outsideScaleUpdate.hands.filter { $0.missingDuration == 0 }.map(\.id), [HandTrackID(rawValue: 2)])

        var retention = HandAssociator(tuning: gateTuning)
        _ = retention.process(
            observations: [SyntheticHand.pose(.pointer).rawObservation(at: 40)],
            at: .init(rawValue: 40)
        )
        XCTAssertEqual(
            retention.process(observations: [], at: .init(rawValue: 40.350)).hands.map(\.id),
            [HandTrackID(rawValue: 1)]
        )
        XCTAssertEqual(
            retention.process(observations: [], at: .init(rawValue: 40.350_001)).hands,
            []
        )
        XCTAssertEqual(
            retention.process(
                observations: [SyntheticHand.pose(.pointer).rawObservation(at: 40.4)],
                at: .init(rawValue: 40.4)
            ).hands.map(\.id),
            [HandTrackID(rawValue: 2)]
        )
    }

    func testOneEuroNumericDuplicateBackwardGapAndJointIsolation() {
        var tuning = GestureTuning.safeDefaults
        tuning.oneEuroMinimumCutoff = 1
        tuning.oneEuroDerivativeCutoff = 1
        tuning.oneEuroBeta = 0
        tuning.normalizedDiscontinuityStep = 10

        var bank = LandmarkFilterBank()
        _ = bank.filter(
            landmarks(wristX: 0, indexX: 0),
            at: .init(rawValue: 1),
            palmWidth: 1,
            tuning: tuning,
            forceReset: true
        )
        let second = bank.filter(
            landmarks(wristX: 0.01, indexX: 0),
            at: .init(rawValue: 1.05),
            palmWidth: 1,
            tuning: tuning,
            forceReset: false
        )
        let alpha = 1 / (1 + (1 / (2 * Double.pi)) / 0.05)
        let expectedSecond = alpha * 0.01
        XCTAssertEqual(second.landmarks[.wrist]?.position.x ?? -1, expectedSecond, accuracy: 1e-12)
        XCTAssertEqual(second.landmarks[.indexTip]?.position.x, 0)

        let duplicate = bank.filter(
            landmarks(wristX: 0.5, indexX: 0.5),
            at: .init(rawValue: 1.05),
            palmWidth: 1,
            tuning: tuning,
            forceReset: false
        )
        XCTAssertFalse(duplicate.resetOccurred)
        XCTAssertEqual(duplicate.landmarks[.wrist]?.position.x ?? -1, expectedSecond, accuracy: 1e-12)
        XCTAssertEqual(duplicate.landmarks[.indexTip]?.position.x, 0)

        let backward = bank.filter(
            landmarks(wristX: 0.4, indexX: 0.4),
            at: .init(rawValue: 1.04),
            palmWidth: 1,
            tuning: tuning,
            forceReset: false
        )
        XCTAssertEqual(backward.landmarks[.wrist]?.position.x ?? -1, expectedSecond, accuracy: 1e-12)

        let third = bank.filter(
            landmarks(wristX: 0.02, indexX: 0),
            at: .init(rawValue: 1.10),
            palmWidth: 1,
            tuning: tuning,
            forceReset: false
        )
        let expectedThird = alpha * 0.02 + (1 - alpha) * expectedSecond
        XCTAssertEqual(third.landmarks[.wrist]?.position.x ?? -1, expectedThird, accuracy: 1e-12)
        XCTAssertEqual(third.landmarks[.indexTip]?.position.x, 0)

        let afterGap = bank.filter(
            landmarks(wristX: 0.03, indexX: 0.02),
            at: .init(rawValue: 1.201),
            palmWidth: 1,
            tuning: tuning,
            forceReset: false
        )
        XCTAssertTrue(afterGap.resetOccurred)
        XCTAssertEqual(afterGap.landmarks[.wrist]?.position.x, 0.03)
        XCTAssertEqual(afterGap.landmarks[.indexTip]?.position.x, 0.02)
    }

    func testPermissionPolicyIsPassiveUntilExplicitPrompt() {
        let provider = FakePermissionSystem()
        let service = PermissionStatusService(system: provider)
        let snapshots = PermissionRecorder()
        service.onChange = { snapshots.append($0) }

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(provider.accessibilityPromptCount, 0)
        XCTAssertEqual(service.refresh(), .init(camera: .notDetermined, accessibilityTrusted: false))
        XCTAssertEqual(service.refresh(), .init(camera: .notDetermined, accessibilityTrusted: false))
        XCTAssertEqual(snapshots.values.count, 1)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(provider.accessibilityPromptCount, 0)

        let completion = BooleanRecorder()
        service.requestCameraAccess { completion.append($0) }
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(completion.values, [true])
        XCTAssertTrue(service.cameraAuthorized)

        service.promptForAccessibility()
        XCTAssertEqual(provider.accessibilityPromptCount, 1)
        XCTAssertTrue(service.accessibilityTrusted)
    }

    func testEmergencyPureChordMarkerDebounceAndHealthPolicy() {
        let chord = EmergencyChordInput(
            charactersIgnoringModifiers: "H",
            control: true,
            option: true,
            command: true
        )
        XCTAssertTrue(EmergencyShortcutPolicy.matches(chord, ignoredMarker: 99))
        var changed = chord
        changed.isRepeat = true
        XCTAssertFalse(EmergencyShortcutPolicy.matches(changed, ignoredMarker: nil))
        changed = chord
        changed.shift = true
        XCTAssertFalse(EmergencyShortcutPolicy.matches(changed, ignoredMarker: nil))
        changed = chord
        changed.eventMarker = 99
        XCTAssertFalse(EmergencyShortcutPolicy.matches(changed, ignoredMarker: 99))
        changed = chord
        changed.charactersIgnoringModifiers = "j"
        XCTAssertFalse(EmergencyShortcutPolicy.matches(changed, ignoredMarker: nil))

        XCTAssertTrue(EmergencyShortcutPolicy.acceptsTrigger(
            uptime: 1, previousUptime: -.infinity, debounceInterval: 0.25
        ))
        XCTAssertFalse(EmergencyShortcutPolicy.acceptsTrigger(
            uptime: 1.24, previousUptime: 1, debounceInterval: 0.25
        ))
        XCTAssertTrue(EmergencyShortcutPolicy.acceptsTrigger(
            uptime: 1.25, previousUptime: 1, debounceInterval: 0.25
        ))
        XCTAssertFalse(EmergencyShortcutPolicy.acceptsTrigger(
            uptime: .nan, previousUptime: 1, debounceInterval: 0.25
        ))

        XCTAssertTrue(EmergencyMonitorHealth(
            globalMonitorInstalled: true, localMonitorInstalled: true
        ).permitsEnable(accessibilityTrusted: true))
        XCTAssertFalse(EmergencyMonitorHealth(
            globalMonitorInstalled: false, localMonitorInstalled: true
        ).permitsEnable(accessibilityTrusted: true))
        XCTAssertTrue(EmergencyMonitorHealth(
            globalMonitorInstalled: false, localMonitorInstalled: true
        ).permitsEnable(accessibilityTrusted: false))
        XCTAssertFalse(EmergencyMonitorHealth(
            globalMonitorInstalled: true, localMonitorInstalled: false
        ).permitsEnable(accessibilityTrusted: false))
    }

    @MainActor
    func testLifecycleOrderingIdempotentStartStopAndLaunchStatusMapping() {
        let monitor = AppLifecycleMonitor()
        let recorder = StringRecorder()
        monitor.onSafetyStop = { recorder.append("safety:\($0.rawValue)") }
        monitor.onSignal = { recorder.append("signal:\($0.rawValue)") }
        monitor.onStatusRefreshRequested = { recorder.append("refresh") }

        monitor.process(.willSleep)
        XCTAssertEqual(recorder.values, ["safety:sleep", "signal:willSleep"])
        recorder.clear()
        monitor.process(.didWake)
        XCTAssertEqual(recorder.values, ["signal:didWake", "refresh"])

        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)

        XCTAssertEqual(LaunchAtLoginController.map(.notRegistered), .notRegistered)
        XCTAssertEqual(LaunchAtLoginController.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginController.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginController.map(.notFound), .notFound)
    }

    func testPureVisionBoundaryMirrorsOnceAndRejectsRequiredAnchors() {
        let points: [LandmarkName: VisionLandmarkPoint] = [
            .wrist: .init(x: 0.2, y: 0.3, confidence: 0.9),
            .indexMCP: .init(x: 0.4, y: 0.5, confidence: 0.8),
            .littleMCP: .init(x: 0.6, y: 0.7, confidence: 0.7),
            .indexTip: .init(x: 0.1, y: 0.9, confidence: 0.95)
        ]
        let mapped = VisionLandmarkBoundary.map(
            points,
            timestamp: .init(rawValue: 5),
            chirality: .left,
            minimumConfidence: 0.6
        )
        XCTAssertEqual(mapped?.timestamp, .init(rawValue: 5))
        XCTAssertEqual(mapped?.chirality, .left)
        XCTAssertEqual(mapped?.landmarks[.wrist]?.position, Point2D(x: 0.8, y: 0.7))
        XCTAssertEqual(mapped?.observationConfidence ?? -1, 0.85, accuracy: 1e-12)

        var missing = points
        missing[.wrist] = nil
        XCTAssertNil(VisionLandmarkBoundary.map(
            missing,
            timestamp: .init(rawValue: 5),
            chirality: .unknown,
            minimumConfidence: 0.6
        ))
        var low = points
        low[.indexMCP] = .init(x: 0.4, y: 0.5, confidence: 0.599)
        XCTAssertNil(VisionLandmarkBoundary.map(
            low,
            timestamp: .init(rawValue: 5),
            chirality: .unknown,
            minimumConfidence: 0.6
        ))
    }

    @MainActor
    func testRealInputLifecycleMatrixAndSettingsChangeReleaseHeldDrag() {
        let reasons: [SafetyStopReason] = [
            .userDisabled, .paused, .emergency, .trackingLost, .cameraStopped,
            .cameraInterrupted, .cameraFailed, .cameraPermissionLost,
            .accessibilityPermissionLost, .sleep, .sessionInactive,
            .displayConfigurationChanged, .shutdown
        ]
        for reason in reasons {
            let (controller, backend) = heldDragController()
            let coordinator = AppCoordinator(
                state: AppState(),
                cameraController: HarnessCameraController(),
                gestureResetter: HarnessGestureResetter(),
                inputController: controller
            )
            coordinator.quiesce(reason: reason)
            XCTAssertFalse(controller.isOutputEnabled, "Gate remained open for \(reason)")
            XCTAssertEqual(controller.snapshot().heldButtons, [])
            XCTAssertEqual(backend.batches().map(\.count), [1, 1])
            XCTAssertEqual(backend.events().filter(isLeftUp).count, 1)
        }

        let (controller, backend) = heldDragController()
        let coordinator = AppCoordinator(
            state: AppState(),
            cameraController: HarnessCameraController(),
            gestureResetter: HarnessGestureResetter(),
            inputController: controller
        )
        coordinator.applySettingsConfiguration(tuning: .safeDefaults, profiles: [])
        XCTAssertFalse(controller.isOutputEnabled)
        XCTAssertEqual(controller.snapshot().heldButtons, [])
        XCTAssertEqual(backend.batches().map(\.count), [1, 1])
        XCTAssertEqual(backend.events().filter(isLeftUp).count, 1)
    }

    private func heldDragController() -> (MacOSInputController, FakeInputBackend) {
        let backend = FakeInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )
        controller.setOutputGate(enabled: true)
        drain(controller)
        controller.handle(.dragStart)
        drain(controller)
        XCTAssertEqual(controller.snapshot().heldButtons, [.left])
        return (controller, backend)
    }

    private func drain(_ controller: MacOSInputController) {
        _ = controller.snapshot()
        _ = controller.snapshot()
    }

    private func isLeftUp(_ event: LowLevelInputEvent) -> Bool {
        if case .mouse(kind: .leftUp, position: _, button: .left, clickState: _) = event {
            return true
        }
        return false
    }

    private func wristX(_ hand: TrackedHandSnapshot?) -> Double {
        hand?.rawLandmarks[.wrist]?.position.x ?? -.infinity
    }

    private func landmarks(wristX: Double, indexX: Double) -> HandLandmarks {
        HandLandmarks(samples: [
            .wrist: LandmarkSample(position: Point2D(x: wristX, y: 0), confidence: 0.95),
            .indexTip: LandmarkSample(position: Point2D(x: indexX, y: 0), confidence: 0.95)
        ])
    }
}

private final class FakePermissionSystem: PermissionSystemProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCamera: CameraPermissionState = .notDetermined
    private var storedAccessibility = false
    private var storedRequests = 0
    private var storedPrompts = 0

    var cameraState: CameraPermissionState { withLock { storedCamera } }
    var accessibilityTrusted: Bool { withLock { storedAccessibility } }
    var requestCount: Int { withLock { storedRequests } }
    var accessibilityPromptCount: Int { withLock { storedPrompts } }

    func requestCameraAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        withLock {
            storedRequests += 1
            storedCamera = .authorized
        }
        completion(true)
    }

    func promptForAccessibility() {
        withLock {
            storedPrompts += 1
            storedAccessibility = true
        }
    }

    @discardableResult
    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class PermissionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PermissionSnapshot] = []
    func append(_ value: PermissionSnapshot) { lock.performLocked { stored.append(value) } }
    var values: [PermissionSnapshot] { lock.performLocked { stored } }
}

private final class BooleanRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Bool] = []
    func append(_ value: Bool) { lock.performLocked { stored.append(value) } }
    var values: [Bool] { lock.performLocked { stored } }
}

private final class StringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ value: String) { lock.performLocked { stored.append(value) } }
    var values: [String] { lock.performLocked { stored } }
    func clear() { lock.performLocked { stored.removeAll() } }
}

private final class HarnessCameraController: CameraControlling {
    func start() {}
    func stop() {}
}

private final class HarnessGestureResetter: GestureResetting {
    func reset(reason: GestureResetReason) -> [GestureEvent] { [.dragEnd] }
}

private extension NSLock {
    func performLocked<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
