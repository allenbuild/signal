import Foundation

public enum CameraAuthorizationState: String, Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

public enum CameraFailure: Equatable, Sendable {
    case noVideoDevice
    case inputCreationFailed(String)
    case cannotAddInput
    case cannotAddOutput
    case sessionStartFailed
    case runtimeError(code: Int, description: String)
    case deviceDisconnected(name: String)
    case configurationFailed(String)
}

public enum CameraServiceState: Equatable, Sendable {
    case stopped
    case starting(generation: UInt64)
    case running(generation: UInt64, deviceName: String)
    case stopping(generation: UInt64)
    case permissionRequired(CameraAuthorizationState)
    case interrupted
    case unavailable(CameraFailure)
    case failed(CameraFailure)
}

/// Monotonic state publication. Consumers reject delayed deliveries whose
/// revision is not newer than the last applied update.
public struct CameraStateUpdate: Equatable, Sendable {
    public var revision: UInt64
    public var state: CameraServiceState

    public init(revision: UInt64, state: CameraServiceState) {
        self.revision = revision
        self.state = state
    }
}

public struct CameraDropCounts: Equatable, Sendable {
    public var avFoundation: UInt64
    public var inactive: UInt64
    public var stale: UInt64
    public var generation: UInt64
    public var backpressure: UInt64
    public var missingConsumer: UInt64

    public init(
        avFoundation: UInt64 = 0,
        inactive: UInt64 = 0,
        stale: UInt64 = 0,
        generation: UInt64 = 0,
        backpressure: UInt64 = 0,
        missingConsumer: UInt64 = 0
    ) {
        self.avFoundation = avFoundation
        self.inactive = inactive
        self.stale = stale
        self.generation = generation
        self.backpressure = backpressure
        self.missingConsumer = missingConsumer
    }

    public var total: UInt64 {
        avFoundation &+ inactive &+ stale &+ generation &+ backpressure &+ missingConsumer
    }
}

public struct CameraDiagnosticsSnapshot: Equatable, Sendable {
    public var generation: UInt64
    public var captureFPS: Double
    public var processedFPS: Double
    public var receivedFrames: UInt64
    public var processedFrames: UInt64
    public var drops: CameraDropCounts
    public var currentInFlight: Int
    public var maximumInFlight: Int
    public var latestProcessingLatencyMilliseconds: Double
    public var latestEndToEndLatencyMilliseconds: Double?

    public init(
        generation: UInt64,
        captureFPS: Double,
        processedFPS: Double,
        receivedFrames: UInt64,
        processedFrames: UInt64,
        drops: CameraDropCounts,
        currentInFlight: Int,
        maximumInFlight: Int,
        latestProcessingLatencyMilliseconds: Double,
        latestEndToEndLatencyMilliseconds: Double?
    ) {
        self.generation = generation
        self.captureFPS = captureFPS
        self.processedFPS = processedFPS
        self.receivedFrames = receivedFrames
        self.processedFrames = processedFrames
        self.drops = drops
        self.currentInFlight = currentInFlight
        self.maximumInFlight = maximumInFlight
        self.latestProcessingLatencyMilliseconds = latestProcessingLatencyMilliseconds
        self.latestEndToEndLatencyMilliseconds = latestEndToEndLatencyMilliseconds
    }

    public static let zero = Self(
        generation: 0,
        captureFPS: 0,
        processedFPS: 0,
        receivedFrames: 0,
        processedFrames: 0,
        drops: .init(),
        currentInFlight: 0,
        maximumInFlight: 0,
        latestProcessingLatencyMilliseconds: 0,
        latestEndToEndLatencyMilliseconds: nil
    )
}
