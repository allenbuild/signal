@preconcurrency import AVFoundation
import CoreMedia
import ImageIO

/// A queue-confined frame lease. Consumers must finish synchronously and must
/// not retain the sample buffer after `consume(_:)` returns.
public struct CapturedFrame {
    public let sampleBuffer: CMSampleBuffer
    public let timestamp: MonotonicTimestamp
    public let orientation: CGImagePropertyOrientation
    public let generation: UInt64

    public init(
        sampleBuffer: CMSampleBuffer,
        timestamp: MonotonicTimestamp,
        orientation: CGImagePropertyOrientation,
        generation: UInt64
    ) {
        self.sampleBuffer = sampleBuffer
        self.timestamp = timestamp
        self.orientation = orientation
        self.generation = generation
    }
}

public protocol CapturedFrameConsuming: AnyObject {
    /// Called on CameraService's serial output queue. Implementations must
    /// perform work synchronously and must not retain `frame.sampleBuffer`.
    func consume(_ frame: CapturedFrame)
}
