import Foundation

public enum GestureEvent: Equatable, Sendable {
    case pointerDelta(dx: Double, dy: Double)
    case leftClick
    case doubleClick
    case dragStart
    case dragDelta(dx: Double, dy: Double)
    case dragEnd
    case rightClick
    case scroll(dx: Double, dy: Double)
    case zoom(delta: Double)
    case trackingLost
}

public protocol InputSink: AnyObject {
    func handle(_ event: GestureEvent)
    func releaseAllInputs()
}

/// Optional stronger input boundary used by live camera pipelines. The sink
/// revalidates the capture lease immediately before posting normal input.
public protocol CaptureGenerationInputSink: InputSink {
    func handle(_ event: GestureEvent, captureGeneration: UInt64)
}

/// Optional normal-output boundary used when a higher-priority gesture starts.
/// It invalidates already queued transient motion without changing explicit
/// enable intent and is deliberately separate from the semantic event enum.
public protocol TransientOutputClutching: InputSink {
    func clutchPendingNormalOutput()
}

/// Stronger non-terminal suspension for a live camera stream whose current
/// recognition result cannot safely drive input. This invalidates queued work
/// and releases owned held input without revoking explicit Control intent.
public protocol TrackingOutputSuspending: InputSink {
    func suspendForTrackingUnavailable()
}

public protocol InputControlling: InputSink {
    func setOutputGate(enabled: Bool)
}
