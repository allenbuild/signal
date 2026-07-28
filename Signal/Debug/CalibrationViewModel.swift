import Combine
import Foundation

public struct InputDiagnosticSnapshot: Equatable, Sendable {
    public var pointerDelta: Point2D?
    public var scrollDelta: Point2D?
    public var zoomDistance: Double?
    public var accumulatedZoomDelta: Double
    public var rawMovement: Double?
    public var normalizedMovement: Double?
    public var filteredMovement: Double?
    public var finalMovement: Double?

    public init(
        pointerDelta: Point2D? = nil,
        scrollDelta: Point2D? = nil,
        zoomDistance: Double? = nil,
        accumulatedZoomDelta: Double = 0,
        rawMovement: Double? = nil,
        normalizedMovement: Double? = nil,
        filteredMovement: Double? = nil,
        finalMovement: Double? = nil
    ) {
        self.pointerDelta = pointerDelta
        self.scrollDelta = scrollDelta
        self.zoomDistance = zoomDistance
        self.accumulatedZoomDelta = accumulatedZoomDelta
        self.rawMovement = rawMovement
        self.normalizedMovement = normalizedMovement
        self.filteredMovement = filteredMovement
        self.finalMovement = finalMovement
    }

    public static let zero = Self()
}

public struct PermissionDiagnosticSnapshot: Equatable, Sendable {
    public var cameraAuthorized: Bool
    public var accessibilityTrusted: Bool

    public init(cameraAuthorized: Bool, accessibilityTrusted: Bool) {
        self.cameraAuthorized = cameraAuthorized
        self.accessibilityTrusted = accessibilityTrusted
    }
}

public struct CalibrationHandOverlay: Equatable, Sendable {
    public var hand: TrackedHandSnapshot
    public var pose: HandPoseSnapshot?

    public init(hand: TrackedHandSnapshot, pose: HandPoseSnapshot?) {
        self.hand = hand
        self.pose = pose
    }
}

public struct CalibrationOverlaySnapshot: Equatable, Sendable {
    public var timestamp: MonotonicTimestamp
    public var hands: [CalibrationHandOverlay]

    public init(timestamp: MonotonicTimestamp, hands: [CalibrationHandOverlay]) {
        self.timestamp = timestamp
        self.hands = hands
    }
}

public struct CalibrationDiagnosticsSnapshot: Equatable, Sendable {
    public var timestamp: MonotonicTimestamp
    public var trackingQuality: TrackingQuality
    public var tracking: TrackingDiagnostics
    public var gestureState: String
    public var zoomEpisode: ZoomEpisodeDiagnostic
    public var gesture: GestureDiagnostics
    public var input: InputDiagnosticSnapshot
    public var permissions: PermissionDiagnosticSnapshot
    public var inputEnabled: Bool

    public init(
        timestamp: MonotonicTimestamp = .init(rawValue: 0),
        trackingQuality: TrackingQuality = .absent,
        tracking: TrackingDiagnostics = .zero,
        gestureState: String = "Idle",
        zoomEpisode: ZoomEpisodeDiagnostic = .inactive,
        gesture: GestureDiagnostics = .safeDefault,
        input: InputDiagnosticSnapshot = .zero,
        permissions: PermissionDiagnosticSnapshot = .init(cameraAuthorized: false, accessibilityTrusted: false),
        inputEnabled: Bool = false
    ) {
        self.timestamp = timestamp
        self.trackingQuality = trackingQuality
        self.tracking = tracking
        self.gestureState = gestureState
        self.zoomEpisode = zoomEpisode
        self.gesture = gesture
        self.input = input
        self.permissions = permissions
        self.inputEnabled = inputEnabled
    }
}

@MainActor
public final class CalibrationViewModel: ObservableObject {
    @Published public private(set) var overlay: CalibrationOverlaySnapshot?
    @Published public private(set) var diagnostics = CalibrationDiagnosticsSnapshot()

    private let overlayInterval: TimeInterval
    private let diagnosticsInterval: TimeInterval
    private var lastOverlayPublish = -Double.infinity
    private var lastDiagnosticsPublish = -Double.infinity
    private var pendingOverlay: CalibrationOverlaySnapshot?
    private var pendingDiagnostics: CalibrationDiagnosticsSnapshot?
    private var overlayTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?

    public init(overlayRate: Double = 15, diagnosticsRate: Double = 10) {
        overlayInterval = 1 / max(1, overlayRate)
        diagnosticsInterval = 1 / max(1, diagnosticsRate)
    }

    /// Accepts immutable values only. Publication keeps at most one pending latest value.
    public func submit(
        tracking: TrackingSnapshot,
        gesture: GestureFrameResult,
        input: InputDiagnosticSnapshot,
        permissions: PermissionDiagnosticSnapshot,
        inputEnabled: Bool
    ) {
        let poseByID = Dictionary(uniqueKeysWithValues: gesture.poses.map { ($0.handID, $0) })
        let nextOverlay = CalibrationOverlaySnapshot(
            timestamp: tracking.timestamp,
            hands: tracking.hands
                .sorted { $0.id < $1.id }
                .map { CalibrationHandOverlay(hand: $0, pose: poseByID[$0.id]) }
        )
        var gestureDiagnostics = gesture.diagnostics
        if gestureDiagnostics.degradationReason == nil {
            gestureDiagnostics.degradationReason = tracking.degradationReason
        }
        let nextDiagnostics = CalibrationDiagnosticsSnapshot(
            timestamp: tracking.timestamp,
            trackingQuality: tracking.quality,
            tracking: tracking.diagnostics,
            gestureState: gesture.stateDescription,
            zoomEpisode: gesture.zoomEpisode,
            gesture: gestureDiagnostics,
            input: input,
            permissions: permissions,
            inputEnabled: inputEnabled
        )

        enqueueOverlay(nextOverlay)
        enqueueDiagnostics(nextDiagnostics)
    }

    public func clear() {
        overlayTask?.cancel()
        diagnosticsTask?.cancel()
        overlayTask = nil
        diagnosticsTask = nil
        pendingOverlay = nil
        pendingDiagnostics = nil
        overlay = nil
        diagnostics = CalibrationDiagnosticsSnapshot()
        lastOverlayPublish = -Double.infinity
        lastDiagnosticsPublish = -Double.infinity
    }

    private func enqueueOverlay(_ value: CalibrationOverlaySnapshot) {
        pendingOverlay = value
        guard overlayTask == nil else { return }
        let delay = max(0, overlayInterval - (ProcessInfo.processInfo.systemUptime - lastOverlayPublish))
        overlayTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            overlay = pendingOverlay
            pendingOverlay = nil
            lastOverlayPublish = ProcessInfo.processInfo.systemUptime
            overlayTask = nil
        }
    }

    private func enqueueDiagnostics(_ value: CalibrationDiagnosticsSnapshot) {
        pendingDiagnostics = value
        guard diagnosticsTask == nil else { return }
        let delay = max(0, diagnosticsInterval - (ProcessInfo.processInfo.systemUptime - lastDiagnosticsPublish))
        diagnosticsTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            diagnostics = pendingDiagnostics ?? diagnostics
            pendingDiagnostics = nil
            lastDiagnosticsPublish = ProcessInfo.processInfo.systemUptime
            diagnosticsTask = nil
        }
    }
}
