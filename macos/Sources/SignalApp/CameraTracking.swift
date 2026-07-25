import AVFoundation
import Foundation
import SignalCore
import Vision

struct CameraDiagnostics: Sendable {
    var captureFPS: Double = 0
    var processedFPS: Double = 0
    var visionLatencyMs: Double = 0
    var endToEndLatencyMs: Double = 0
    var droppedFrames: Int = 0
}

final class CameraHandTrackingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.signal.camera", qos: .userInteractive)
    private let sequenceHandler = VNSequenceRequestHandler()
    private var processing = false
    private var lastCaptureAt: TimeInterval?
    private var lastProcessedAt: TimeInterval?
    private(set) var diagnostics = CameraDiagnostics()
    var onHand: (@Sendable (HandLandmarks, CameraDiagnostics) -> Void)?
    var onTrackingLoss: (@Sendable () -> Void)?

    func requestAndStart() async -> Bool {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        guard authorized else { return false }
        return await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try self.configureIfNeeded()
                    self.session.startRunning()
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.processing = false
        }
    }

    private func configureIfNeeded() throws {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.unavailable
        }
        try device.lockForConfiguration()
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
        device.unlockForConfiguration()
        session.addInput(try AVCaptureDeviceInput(device: device))
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastCaptureAt {
            diagnostics.captureFPS = smooth(diagnostics.captureFPS, 1 / max(now - lastCaptureAt, 0.001))
        }
        lastCaptureAt = now
        guard !processing else {
            diagnostics.droppedFrames += 1
            return
        }
        processing = true
        defer { processing = false }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try sequenceHandler.perform([request], on: sampleBuffer, orientation: .upMirrored)
            let finished = ProcessInfo.processInfo.systemUptime
            diagnostics.visionLatencyMs = smooth(diagnostics.visionLatencyMs, (finished - started) * 1_000)
            if let lastProcessedAt {
                diagnostics.processedFPS = smooth(diagnostics.processedFPS, 1 / max(finished - lastProcessedAt, 0.001))
            }
            lastProcessedAt = finished
            guard let observation = request.results?.first,
                  let landmarks = Self.landmarks(from: observation, timestamp: finished) else {
                onTrackingLoss?()
                return
            }
            diagnostics.endToEndLatencyMs = diagnostics.visionLatencyMs
            onHand?(landmarks, diagnostics)
        } catch {
            onTrackingLoss?()
        }
    }

    private static func landmarks(
        from observation: VNHumanHandPoseObservation,
        timestamp: TimeInterval
    ) -> HandLandmarks? {
        let mapping: [HandJoint: VNHumanHandPoseObservation.JointName] = [
            .wrist: .wrist,
            .thumbCMC: .thumbCMC, .thumbMP: .thumbMP, .thumbIP: .thumbIP, .thumbTip: .thumbTip,
            .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexDIP: .indexDIP, .indexTip: .indexTip,
            .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleDIP: .middleDIP, .middleTip: .middleTip,
            .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringDIP: .ringDIP, .ringTip: .ringTip,
            .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleDIP: .littleDIP, .littleTip: .littleTip
        ]
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var joints: [HandJoint: JointSample] = [:]
        for (joint, visionName) in mapping {
            guard let point = recognized[visionName] else { continue }
            joints[joint] = JointSample(
                Point2D(x: point.location.x, y: point.location.y),
                confidence: Double(point.confidence)
            )
        }
        let handedness: Handedness = observation.chirality == .left ? .left : .right
        return HandLandmarks(handedness: handedness, joints: joints, timestamp: timestamp)
    }

    private func smooth(_ old: Double, _ new: Double) -> Double {
        old == 0 ? new : old * 0.85 + new * 0.15
    }
}

private enum CameraError: Error {
    case unavailable
}
