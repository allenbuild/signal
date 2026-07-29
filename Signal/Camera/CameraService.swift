@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import OSLog

public final class CameraService: NSObject, CameraControlling,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    public typealias StateHandler = @Sendable (CameraServiceState) -> Void
    public typealias StateUpdateHandler = @Sendable (CameraStateUpdate) -> Void
    public typealias DiagnosticsHandler = @Sendable (CameraDiagnosticsSnapshot) -> Void

    private static let targetFrameRate: Int32 = 30
    private static let diagnosticsIntervalSeconds = 0.250

    private let logger = Logger(subsystem: "com.allenxu.Signal", category: "Camera")
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.allenxu.Signal.camera.session")
    private let outputQueue = DispatchQueue(
        label: "com.allenxu.Signal.camera.output",
        autoreleaseFrequency: .workItem
    )
    private let sessionQueueKey = DispatchSpecificKey<UInt8>()
    private let runGate = CameraRunGate()
    private let stateDeliveryQueue = DispatchQueue(label: "com.allenxu.Signal.camera.state")

    private let sharedStateLock = NSLock()
    private var _state: CameraServiceState = .stopped
    private var _stateRevision: UInt64 = 0
    private var _onStateChange: StateHandler?
    private var _onStateUpdate: StateUpdateHandler?
    private var _onDiagnostics: DiagnosticsHandler?
    private weak var _frameConsumer: CapturedFrameConsuming?
    private var configuredDeviceID: String?

    private let diagnosticsLock = NSLock()
    private var _latestDiagnostics: CameraDiagnosticsSnapshot = .zero

    // sessionQueue only
    private var isConfigured = false
    private var needsRebuild = false
    private var deviceInput: AVCaptureDeviceInput?
    private var observerTokens: [NSObjectProtocol] = []

    // outputQueue only
    private var isProcessingFrame = false
    private var metrics = CameraMetrics()

    public override init() {
        super.init()
        finishInitialization()
    }

    public init(frameConsumer: CapturedFrameConsuming) {
        _frameConsumer = frameConsumer
        super.init()
        finishInitialization()
    }

    deinit {
        runGate.requestStop(terminalState: .stopped, forceGeneration: true)
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        videoOutput.setSampleBufferDelegate(nil, queue: nil)

        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            stopAndTearDownOnSessionQueue()
        } else {
            sessionQueue.sync { stopAndTearDownOnSessionQueue() }
        }
    }

    public var onStateChange: StateHandler? {
        get { withSharedStateLock { _onStateChange } }
        set { withSharedStateLock { _onStateChange = newValue } }
    }

    public var onStateUpdate: StateUpdateHandler? {
        get { withSharedStateLock { _onStateUpdate } }
        set { withSharedStateLock { _onStateUpdate = newValue } }
    }

    public var onDiagnostics: DiagnosticsHandler? {
        get { withSharedStateLock { _onDiagnostics } }
        set { withSharedStateLock { _onDiagnostics = newValue } }
    }

    public var state: CameraServiceState {
        withSharedStateLock { _state }
    }

    public var stateUpdate: CameraStateUpdate {
        withSharedStateLock { CameraStateUpdate(revision: _stateRevision, state: _state) }
    }

    public var latestDiagnostics: CameraDiagnosticsSnapshot {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return _latestDiagnostics
    }

    public var currentGeneration: UInt64 {
        runGate.snapshot().generation
    }

    public var authorizationState: CameraAuthorizationState {
        Self.authorizationState(for: AVCaptureDevice.authorizationStatus(for: .video))
    }

    public func setFrameConsumer(_ consumer: CapturedFrameConsuming?) {
        withSharedStateLock { _frameConsumer = consumer }
    }

    /// Returns false for a stopped, faulted, or superseded frame generation.
    /// Downstream consumers should check this before publishing derived values.
    public func isGenerationCurrent(_ generation: UInt64) -> Bool {
        runGate.isCurrent(generation, requiringRunning: true)
    }

    /// Starts only when camera authorization is already granted. Permission
    /// prompting belongs to the Permissions module and a later explicit start.
    public func start() {
        let authorization = authorizationState
        guard authorization == .authorized else {
            let terminalState = CameraServiceState.permissionRequired(authorization)
            runGate.requestStop(terminalState: terminalState, forceGeneration: true)
            publishState(terminalState)
            enqueueReconcile()
            return
        }

        let target = runGate.requestStart()
        publishState(.starting(generation: target.generation))
        outputQueue.async { [weak self] in
            guard let self else { return }
            let now = self.hostTimeSeconds()
            self.metrics.reset(generation: target.generation, now: now)
            self.publishDiagnosticsIfNeeded(now: now, force: true)
        }
        enqueueReconcile()
    }

    public func stop() {
        let target = runGate.requestStop(terminalState: .stopped)
        publishState(.stopping(generation: target.generation))
        enqueueReconcile()
    }

    /// Call after a permission-status refresh. Authorization recovery does not
    /// restart capture; the user/coordinator must issue another explicit start.
    public func authorizationDidChange() {
        let authorization = authorizationState
        let terminalState: CameraServiceState = authorization == .authorized
            ? .stopped
            : .permissionRequired(authorization)
        runGate.requestStop(terminalState: terminalState, forceGeneration: true)
        publishState(terminalState)
        enqueueReconcile()
    }

    @MainActor
    public func makePreviewLayerController() -> CameraPreviewLayerController {
        CameraPreviewLayerController(session: captureSession)
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dispatchPrecondition(condition: .onQueue(outputQueue))
        let callbackTime = hostTimeSeconds()
        metrics.recordReceived(at: callbackTime)

        let target = runGate.snapshot()
        guard target.desiredRunning else {
            metrics.drops.inactive &+= 1
            publishDiagnosticsIfNeeded(now: callbackTime)
            return
        }

        guard let sourceTiming = sourceTiming(for: sampleBuffer, hostNow: callbackTime) else {
            metrics.drops.stale &+= 1
            publishDiagnosticsIfNeeded(now: callbackTime)
            return
        }
        guard metrics.frameFreshnessGate.accepts(sourceTiming.ageSeconds) else {
            metrics.drops.stale &+= 1
            publishDiagnosticsIfNeeded(now: callbackTime)
            return
        }

        guard !isProcessingFrame else {
            metrics.drops.backpressure &+= 1
            publishDiagnosticsIfNeeded(now: callbackTime)
            return
        }
        guard let consumer = currentFrameConsumer() else {
            metrics.drops.missingConsumer &+= 1
            publishDiagnosticsIfNeeded(now: callbackTime)
            return
        }

        isProcessingFrame = true
        metrics.currentInFlight = 1
        metrics.maximumInFlight = max(metrics.maximumInFlight, metrics.currentInFlight)
        defer {
            metrics.currentInFlight = 0
            isProcessingFrame = false
            publishDiagnosticsIfNeeded(now: hostTimeSeconds())
        }

        let frame = CapturedFrame(
            sampleBuffer: sampleBuffer,
            timestamp: sourceTiming.timestamp,
            orientation: .up,
            generation: target.generation
        )
        let processingStart = hostTimeSeconds()
        autoreleasepool {
            consumer.consume(frame)
        }
        let processingEnd = hostTimeSeconds()
        metrics.latestProcessingLatencyMilliseconds = max(
            0,
            (processingEnd - processingStart) * 1_000
        )

        guard runGate.isCurrent(target.generation, requiringRunning: true) else {
            metrics.drops.generation &+= 1
            return
        }

        metrics.recordProcessed(at: processingEnd)
        if sourceTiming.isHostClockTime {
            metrics.latestEndToEndLatencyMilliseconds = max(
                0,
                (processingEnd - sourceTiming.timestamp.rawValue) * 1_000
            )
        } else {
            metrics.latestEndToEndLatencyMilliseconds = nil
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dispatchPrecondition(condition: .onQueue(outputQueue))
        metrics.drops.avFoundation &+= 1
        publishDiagnosticsIfNeeded(now: hostTimeSeconds())
    }

    private func finishInitialization() {
        sessionQueue.setSpecific(key: sessionQueueKey, value: 1)
        installObservers()
    }

    private func enqueueReconcile(rebuild: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if rebuild {
                self.needsRebuild = true
            }
            self.reconcileUntilStable()
        }
    }

    private func reconcileUntilStable() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))

        while true {
            let target = runGate.snapshot()
            if target.desiredRunning {
                let authorization = authorizationState
                guard authorization == .authorized else {
                    runGate.requestStop(
                        terminalState: .permissionRequired(authorization),
                        forceGeneration: true
                    )
                    continue
                }

                do {
                    if needsRebuild {
                        stopAndTearDownOnSessionQueue()
                        needsRebuild = false
                    }
                    try configureSessionIfNeeded()
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                    guard captureSession.isRunning else {
                        throw CameraConfigurationError.failure(.sessionStartFailed)
                    }
                } catch let error as CameraConfigurationError {
                    needsRebuild = true
                    let terminalState: CameraServiceState = error.failure == .noVideoDevice
                        ? .unavailable(error.failure)
                        : .failed(error.failure)
                    runGate.requestStop(
                        terminalState: terminalState,
                        forceGeneration: true
                    )
                    continue
                } catch {
                    needsRebuild = true
                    runGate.requestStop(
                        terminalState: .failed(.configurationFailed(error.localizedDescription)),
                        forceGeneration: true
                    )
                    continue
                }

                let deviceName = deviceInput?.device.localizedName ?? "Camera"
                let didPublish = runGate.withCurrent(
                    target.generation,
                    requiringRunning: true
                ) {
                    publishState(.running(
                        generation: target.generation,
                        deviceName: deviceName
                    ))
                }
                if didPublish { return }
                continue
            }

            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            if needsRebuild {
                tearDownSessionOnSessionQueue()
                needsRebuild = false
            }

            let latest = runGate.snapshot()
            guard latest.generation == target.generation,
                  latest.desiredRunning == target.desiredRunning else {
                continue
            }
            publishState(latest.terminalState)
            return
        }
    }

    private func configureSessionIfNeeded() throws {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard !isConfigured else { return }

        guard let device = Self.selectVideoDevice() else {
            throw CameraConfigurationError.failure(.noVideoDevice)
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraConfigurationError.failure(.inputCreationFailed(error.localizedDescription))
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        }
        guard captureSession.canAddInput(input) else {
            throw CameraConfigurationError.failure(.cannotAddInput)
        }
        captureSession.addInput(input)

        // Leave videoSettings empty on macOS so AVFoundation supplies a
        // device-native, Vision-compatible format without conversion.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraConfigurationError.failure(.cannotAddOutput)
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
            let frameDuration = CMTime(value: 1, timescale: Self.targetFrameRate)
            if connection.isVideoMinFrameDurationSupported {
                connection.videoMinFrameDuration = frameDuration
            }
            if connection.isVideoMaxFrameDurationSupported {
                connection.videoMaxFrameDuration = frameDuration
            }
        }

        deviceInput = input
        setConfiguredDeviceID(device.uniqueID)
        isConfigured = true
        logger.info("Configured camera capture at VGA target and 30 FPS")
    }

    private static func selectVideoDevice() -> AVCaptureDevice? {
        let front = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        ).devices.first
        // v1's fixed Vision orientation is validated only for the built-in
        // front-facing camera. Unknown/external orientations fail closed.
        return front
    }

    private func stopAndTearDownOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        tearDownSessionOnSessionQueue()
    }

    private func tearDownSessionOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        captureSession.beginConfiguration()
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        captureSession.commitConfiguration()
        deviceInput = nil
        setConfiguredDeviceID(nil)
        isConfigured = false
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: captureSession,
            queue: nil
        ) { [weak self] notification in
            self?.handleRuntimeError(notification)
        })
        observerTokens.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: captureSession,
            queue: nil
        ) { [weak self] _ in
            self?.handleInterruption()
        })
        observerTokens.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: captureSession,
            queue: nil
        ) { [weak self] _ in
            self?.handleInterruptionEnded()
        })
        observerTokens.append(center.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleDeviceDisconnected(notification)
        })
        observerTokens.append(center.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleDeviceConnected()
        })
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let failure = CameraFailure.runtimeError(
            code: error?.code ?? -1,
            description: error?.localizedDescription ?? "Unknown capture runtime error"
        )
        let terminalState = CameraServiceState.failed(failure)
        runGate.requestStop(terminalState: terminalState, forceGeneration: true)
        publishState(terminalState)
        logger.error("Capture runtime failure: \(error?.code ?? -1, privacy: .public)")
        enqueueReconcile(rebuild: true)
    }

    private func handleInterruption() {
        runGate.requestStop(terminalState: .interrupted, forceGeneration: true)
        publishState(.interrupted)
        logger.notice("Capture session interrupted")
        enqueueReconcile()
    }

    private func handleInterruptionEnded() {
        runGate.requestStop(terminalState: .stopped, forceGeneration: true)
        publishState(.stopped)
        logger.notice("Capture session interruption ended; explicit restart required")
        enqueueReconcile()
    }

    private func handleDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              isConfiguredDevice(id: device.uniqueID) else { return }
        let terminalState = CameraServiceState.unavailable(
            .deviceDisconnected(name: device.localizedName)
        )
        runGate.requestStop(terminalState: terminalState, forceGeneration: true)
        publishState(terminalState)
        logger.error("Configured camera disconnected")
        enqueueReconcile(rebuild: true)
    }

    private func handleDeviceConnected() {
        guard case .unavailable = state else { return }
        runGate.requestStop(terminalState: .stopped, forceGeneration: true)
        publishState(.stopped)
        logger.info("A video device connected; explicit restart required")
        enqueueReconcile(rebuild: true)
    }

    private func sourceTiming(
        for sampleBuffer: CMSampleBuffer,
        hostNow: Double
    ) -> (timestamp: MonotonicTimestamp, ageSeconds: Double?, isHostClockTime: Bool)? {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric else { return nil }

        let hostClock = CMClockGetHostTimeClock()
        if let synchronizationClock = captureSession.synchronizationClock {
            let converted = CMSyncConvertTime(
                presentationTime,
                from: synchronizationClock,
                to: hostClock
            )
            let seconds = CMTimeGetSeconds(converted)
            if converted.isValid, converted.isNumeric, seconds.isFinite {
                return (
                    MonotonicTimestamp(rawValue: seconds),
                    hostNow - seconds,
                    true
                )
            }
        }

        let seconds = CMTimeGetSeconds(presentationTime)
        guard seconds.isFinite else { return nil }
        return (MonotonicTimestamp(rawValue: seconds), nil, false)
    }

    private func hostTimeSeconds() -> Double {
        CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    }

    private func publishState(_ newState: CameraServiceState) {
        withSharedStateLock {
            guard _state != newState else { return }
            _state = newState
            _stateRevision &+= 1
            let update = CameraStateUpdate(revision: _stateRevision, state: newState)
            let callback = _onStateChange
            let updateCallback = _onStateUpdate
            // Enqueue while holding the state lock so concurrent publishers
            // cannot invert callback order.
            stateDeliveryQueue.async {
                updateCallback?(update)
                callback?(newState)
            }
        }
    }

    private func publishDiagnosticsIfNeeded(now: Double, force: Bool = false) {
        guard force || metrics.shouldPublish(now: now, interval: Self.diagnosticsIntervalSeconds) else {
            return
        }
        let snapshot = metrics.snapshot
        diagnosticsLock.lock()
        _latestDiagnostics = snapshot
        diagnosticsLock.unlock()
        let callback = withSharedStateLock { _onDiagnostics }
        callback?(snapshot)
    }

    private func currentFrameConsumer() -> CapturedFrameConsuming? {
        withSharedStateLock { _frameConsumer }
    }

    private func setConfiguredDeviceID(_ id: String?) {
        withSharedStateLock { configuredDeviceID = id }
    }

    private func isConfiguredDevice(id: String) -> Bool {
        withSharedStateLock { configuredDeviceID == id }
    }

    @discardableResult
    private func withSharedStateLock<T>(_ body: () throws -> T) rethrows -> T {
        sharedStateLock.lock()
        defer { sharedStateLock.unlock() }
        return try body()
    }

    private static func authorizationState(
        for status: AVAuthorizationStatus
    ) -> CameraAuthorizationState {
        switch status {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }
}

private enum CameraConfigurationError: Error {
    case failure(CameraFailure)

    var failure: CameraFailure {
        switch self {
        case let .failure(failure): failure
        }
    }
}

private final class CameraRunGate: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        var desiredRunning: Bool
        var generation: UInt64
        var terminalState: CameraServiceState
    }

    private let lock = NSLock()
    private var desiredRunning = false
    private var generation: UInt64 = 0
    private var terminalState: CameraServiceState = .stopped

    func requestStart() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if !desiredRunning {
            generation &+= 1
            desiredRunning = true
        }
        return currentSnapshot
    }

    @discardableResult
    func requestStop(
        terminalState: CameraServiceState,
        forceGeneration: Bool = false
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if desiredRunning || forceGeneration || self.terminalState != terminalState {
            generation &+= 1
        }
        desiredRunning = false
        self.terminalState = terminalState
        return currentSnapshot
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshot
    }

    func isCurrent(_ candidate: UInt64, requiringRunning: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == candidate && (!requiringRunning || desiredRunning)
    }


    @discardableResult
    func withCurrent(
        _ candidate: UInt64,
        requiringRunning: Bool,
        _ body: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == candidate, !requiringRunning || desiredRunning else { return false }
        body()
        return true
    }

    private var currentSnapshot: Snapshot {
        Snapshot(
            desiredRunning: desiredRunning,
            generation: generation,
            terminalState: terminalState
        )
    }
}

private struct CameraMetrics {
    var generation: UInt64 = 0
    var receivedFrames: UInt64 = 0
    var processedFrames: UInt64 = 0
    var drops = CameraDropCounts()
    var currentInFlight = 0
    var maximumInFlight = 0
    var latestProcessingLatencyMilliseconds = 0.0
    var latestEndToEndLatencyMilliseconds: Double?
    var captureRate = FrameRateMeter()
    var processedRate = FrameRateMeter()
    var frameFreshnessGate = CameraFrameFreshnessGate()
    var lastPublishedAt = -Double.infinity

    mutating func reset(generation: UInt64, now: Double) {
        self = CameraMetrics()
        frameFreshnessGate.reset()
        self.generation = generation
        captureRate.reset(at: now)
        processedRate.reset(at: now)
        lastPublishedAt = now
    }

    mutating func recordReceived(at now: Double) {
        receivedFrames &+= 1
        captureRate.record(at: now)
    }

    mutating func recordProcessed(at now: Double) {
        processedFrames &+= 1
        processedRate.record(at: now)
    }

    mutating func shouldPublish(now: Double, interval: Double) -> Bool {
        guard now - lastPublishedAt >= interval else { return false }
        lastPublishedAt = now
        return true
    }

    var snapshot: CameraDiagnosticsSnapshot {
        CameraDiagnosticsSnapshot(
            generation: generation,
            captureFPS: captureRate.framesPerSecond,
            processedFPS: processedRate.framesPerSecond,
            receivedFrames: receivedFrames,
            processedFrames: processedFrames,
            drops: drops,
            currentInFlight: currentInFlight,
            maximumInFlight: maximumInFlight,
            latestProcessingLatencyMilliseconds: latestProcessingLatencyMilliseconds,
            latestEndToEndLatencyMilliseconds: latestEndToEndLatencyMilliseconds
        )
    }
}

/// Adapts the stale-frame threshold to the stable clock offset observed for a
/// capture generation while retaining a hard upper latency bound.
struct CameraFrameFreshnessGate: Equatable, Sendable {
    static let absoluteLimitSeconds = 0.150
    static let relativeLimitSeconds = 0.066

    private(set) var minimumObservedAgeSeconds: Double?

    mutating func accepts(_ ageSeconds: Double?) -> Bool {
        guard let ageSeconds else { return true }
        guard ageSeconds.isFinite, ageSeconds >= 0 else { return false }

        let minimum = min(minimumObservedAgeSeconds ?? ageSeconds, ageSeconds)
        minimumObservedAgeSeconds = minimum
        return ageSeconds <= Self.absoluteLimitSeconds
            && ageSeconds <= minimum + Self.relativeLimitSeconds
    }

    mutating func reset() {
        self = CameraFrameFreshnessGate()
    }
}

private struct FrameRateMeter {
    private(set) var framesPerSecond = 0.0
    private var windowStartedAt = 0.0
    private var framesInWindow: UInt64 = 0

    mutating func reset(at now: Double) {
        framesPerSecond = 0
        windowStartedAt = now
        framesInWindow = 0
    }

    mutating func record(at now: Double) {
        if windowStartedAt == 0 {
            windowStartedAt = now
        }
        framesInWindow &+= 1
        let elapsed = now - windowStartedAt
        guard elapsed >= 1 else { return }
        framesPerSecond = Double(framesInWindow) / elapsed
        windowStartedAt = now
        framesInWindow = 0
    }
}
