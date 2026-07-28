import CoreMedia
import Foundation
import ImageIO
@preconcurrency import Vision

/// Synchronous, serial-context tracking pipeline.
///
/// The caller must invoke processing and reset methods from one serial capture/
/// Vision context. `CMSampleBuffer` is consumed before the method returns and is
/// never retained or sent through a Swift task/actor boundary.
public final class TrackingService: CapturedFrameConsuming, @unchecked Sendable {
    private static let maximumEndToEndFrameAge: TimeInterval = 0.150

    public var onSnapshot: (@Sendable (TrackingSnapshot) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return snapshotCallback
        }
        set {
            callbackLock.lock()
            snapshotCallback = newValue
            callbackLock.unlock()
        }
    }

    /// A final, synchronous lease check performed immediately before a
    /// snapshot leaves Tracking. CameraService supplies this validator so work
    /// from a stopped or superseded capture generation can never reach gesture
    /// or input processing.
    public var generationValidator: (@Sendable (UInt64) -> Bool)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return _generationValidator
        }
        set {
            callbackLock.lock()
            _generationValidator = newValue
            callbackLock.unlock()
        }
    }

    private let callbackLock = NSLock()
    private var snapshotCallback: (@Sendable (TrackingSnapshot) -> Void)?
    private var _generationValidator: (@Sendable (UInt64) -> Bool)?
    private let stateLock = NSRecursiveLock()
    private let request: VNDetectHumanHandPoseRequest
    private var mapper: VisionHandPoseMapper
    private var associator: HandAssociator
    private var diagnostics = TrackingDiagnosticsAccumulator()
    private var tuning: GestureTuning
    private var activeGeneration: UInt64?
    private var lastTimestamp: MonotonicTimestamp?
    private let currentUptime: @Sendable () -> Double

    public convenience init(tuning: GestureTuning = .safeDefaults) {
        self.init(
            tuning: tuning,
            currentUptime: { ProcessInfo.processInfo.systemUptime }
        )
    }

    init(
        tuning: GestureTuning,
        currentUptime: @escaping @Sendable () -> Double
    ) {
        let tuning = tuning.validated()
        self.tuning = tuning
        self.currentUptime = currentUptime
        mapper = VisionHandPoseMapper(minimumConfidence: tuning.minimumLandmarkConfidence)
        associator = HandAssociator(tuning: tuning)

        let request = VNDetectHumanHandPoseRequest()
        request.revision = VNDetectHumanHandPoseRequestRevision1
        request.maximumHandCount = 2
        self.request = request
    }

    public func update(tuning: GestureTuning) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let validated = tuning.validated()
        self.tuning = validated
        mapper.minimumConfidence = validated.minimumLandmarkConfidence
        associator.update(tuning: validated)
        diagnostics.resetProcessing()
        lastTimestamp = nil
    }

    public func updateCameraDiagnostics(captureFPS: Double, droppedFrames: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        diagnostics.updateCamera(captureFPS: captureFPS, droppedFrames: droppedFrames)
    }

    public func consume(_ frame: CapturedFrame) {
        process(
            sampleBuffer: frame.sampleBuffer,
            timestamp: frame.timestamp,
            orientation: frame.orientation,
            generation: frame.generation
        )
    }

    /// Platform-field convenience entry point for direct integration checks.
    @discardableResult
    public func process(
        sampleBuffer: CMSampleBuffer,
        timestamp: MonotonicTimestamp,
        orientation: CGImagePropertyOrientation,
        generation: UInt64
    ) -> TrackingSnapshot? {
        stateLock.lock()
        defer { stateLock.unlock() }
        prepare(generation: generation)
        guard accepts(timestamp: timestamp) else {
            diagnostics.recordDrop()
            return nil
        }

        let visionStart = currentUptime()
        let mapping: VisionMappingResult
        do {
            mapping = try autoreleasepool {
                let handler = VNImageRequestHandler(
                    cmSampleBuffer: sampleBuffer,
                    orientation: orientation,
                    options: [:]
                )
                try handler.perform([request])
                return mapper.map(request.results ?? [], timestamp: timestamp)
            }
        } catch {
            diagnostics.recordDrop()
            let completion = currentUptime()
            let snapshot = makeSnapshot(
                observations: [],
                rejectionReasons: [.visionFailure],
                generation: generation,
                timestamp: timestamp,
                visionLatencyMilliseconds: (completion - visionStart) * 1_000,
                completionUptime: completion,
                enforceFrameAge: true,
                dropAlreadyRecorded: true
            )
            publish(snapshot, generation: generation)
            return snapshot
        }

        let completion = currentUptime()
        let visionLatency = (completion - visionStart) * 1_000
        let snapshot = makeSnapshot(
            observations: mapping.observations,
            rejectionReasons: mapping.rejectionReasons,
            generation: generation,
            timestamp: timestamp,
            visionLatencyMilliseconds: visionLatency,
            completionUptime: completion,
            enforceFrameAge: true
        )
        publish(snapshot, generation: generation)
        return snapshot
    }

    /// Deterministic seam for synthetic mapping/association/filter tests.
    @discardableResult
    public func process(
        rawObservations: [RawHandObservation],
        timestamp: MonotonicTimestamp,
        generation: UInt64
    ) -> TrackingSnapshot? {
        stateLock.lock()
        defer { stateLock.unlock() }
        prepare(generation: generation)
        guard accepts(timestamp: timestamp) else {
            diagnostics.recordDrop()
            return nil
        }
        let snapshot = makeSnapshot(
            observations: rawObservations,
            rejectionReasons: [],
            generation: generation,
            timestamp: timestamp,
            visionLatencyMilliseconds: 0,
            completionUptime: currentUptime(),
            enforceFrameAge: false
        )
        publish(snapshot, generation: generation)
        return snapshot
    }

    /// Deterministic seam for exercising mapper rejection alongside accepted
    /// hands without requiring Vision framework observations.
    @discardableResult
    func process(
        rawObservations: [RawHandObservation],
        rejectionReasons: [TrackingDegradationReason],
        timestamp: MonotonicTimestamp,
        generation: UInt64,
        enforceFrameAge: Bool = false
    ) -> TrackingSnapshot? {
        stateLock.lock()
        defer { stateLock.unlock() }
        prepare(generation: generation)
        guard accepts(timestamp: timestamp) else {
            diagnostics.recordDrop()
            return nil
        }
        let snapshot = makeSnapshot(
            observations: rawObservations,
            rejectionReasons: rejectionReasons,
            generation: generation,
            timestamp: timestamp,
            visionLatencyMilliseconds: 0,
            completionUptime: currentUptime(),
            enforceFrameAge: enforceFrameAge
        )
        publish(snapshot, generation: generation)
        return snapshot
    }

    public func reset(reason: TrackingResetReason) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _ = reason
        associator.reset()
        diagnostics.resetProcessing()
        activeGeneration = nil
        lastTimestamp = nil
    }

    private func prepare(generation: UInt64) {
        guard activeGeneration != generation else { return }
        activeGeneration = generation
        associator.reset()
        diagnostics.resetProcessing()
        lastTimestamp = nil
    }

    private func accepts(timestamp: MonotonicTimestamp) -> Bool {
        guard timestamp.rawValue.isFinite else { return false }
        if let lastTimestamp, timestamp <= lastTimestamp {
            return false
        }
        self.lastTimestamp = timestamp
        return true
    }

    private func makeSnapshot(
        observations: [RawHandObservation],
        rejectionReasons: [TrackingDegradationReason],
        generation: UInt64,
        timestamp: MonotonicTimestamp,
        visionLatencyMilliseconds: Double,
        completionUptime: Double,
        enforceFrameAge: Bool,
        dropAlreadyRecorded: Bool = false
    ) -> TrackingSnapshot {
        diagnostics.recordProcessed(
            completionUptime: completionUptime,
            sourceTimestamp: timestamp,
            visionLatencyMilliseconds: visionLatencyMilliseconds
        )

        if enforceFrameAge, isStale(timestamp: timestamp, completionUptime: completionUptime) {
            // Vision completed, but its source image is now too old to update
            // identity/filter state or produce normal gesture output. Publish a
            // degraded snapshot so the prior good watchdog arm remains the
            // terminal safety fence.
            if !dropAlreadyRecorded {
                diagnostics.recordDrop()
            }
            let retained = associator.currentSnapshot(at: timestamp)
            return TrackingSnapshot(
                captureGeneration: generation,
                timestamp: timestamp,
                hands: retained.hands,
                quality: .degraded,
                diagnostics: diagnostics.snapshot(at: completionUptime),
                degradationReason: .staleFrame
            )
        }

        let association = associator.process(observations: observations, at: timestamp)

        let degradationReason: TrackingDegradationReason?
        if association.quality == .good {
            // A valid current hand is sufficient for one-hand tracking. A
            // rejected partial/spurious second observation is diagnostic noise,
            // not a reason to poison the accepted hand's identity quality.
            degradationReason = nil
        } else if observations.isEmpty, let mappedRejection = rejectionReasons.first {
            degradationReason = mappedRejection
        } else {
            degradationReason = association.degradationReason ?? rejectionReasons.first
        }

        return TrackingSnapshot(
            captureGeneration: generation,
            timestamp: timestamp,
            hands: association.hands,
            quality: association.quality,
            diagnostics: diagnostics.snapshot(at: completionUptime),
            degradationReason: degradationReason
        )
    }

    private func isStale(
        timestamp: MonotonicTimestamp,
        completionUptime: Double
    ) -> Bool {
        let age = completionUptime - timestamp.rawValue
        return !age.isFinite
            || age < 0
            || age > Self.maximumEndToEndFrameAge
    }

    private func publish(_ snapshot: TrackingSnapshot, generation: UInt64) {
        callbackLock.lock()
        let callback = snapshotCallback
        let validator = _generationValidator
        callbackLock.unlock()
        guard validator?(generation) ?? true else { return }
        callback?(snapshot)
    }
}
