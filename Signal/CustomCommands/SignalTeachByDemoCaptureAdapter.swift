import Foundation

public struct SignalTeachByDemoApplication:
    Equatable,
    Sendable
{
    public var processIdentifier: Int32
    public var bundleIdentifier: String
    public var localizedName: String

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String,
        localizedName: String
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

public struct SignalTeachByDemoScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SignalTeachByDemoCapturedEvent: Equatable, Sendable {
    case primaryPointerReleased(at: SignalTeachByDemoScreenPoint)
    case keyDown(
        keyCode: Int64,
        text: String?,
        modifiers: Set<SignalTeachByDemoModifier>,
        isRepeat: Bool
    )
    case secureKeyboardInput
}

public struct SignalTeachByDemoResolvedTarget: Equatable, Sendable {
    public var target: SignalReviewedAccessibilityTarget
    public var isReviewed: Bool

    public init(
        target: SignalReviewedAccessibilityTarget,
        isReviewed: Bool
    ) {
        self.target = target
        self.isReviewed = isReviewed
    }
}

@MainActor
public protocol SignalTeachByDemoEventCapturing: AnyObject {
    func start(
        handler: @escaping @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    ) throws
    func stop()
}

@MainActor
public protocol SignalTeachByDemoApplicationObserving: AnyObject {
    var frontmostApplication: SignalTeachByDemoApplication? { get }

    func start(
        handler: @escaping @MainActor (SignalTeachByDemoApplication) -> Void
    )
    func stop()
}

@MainActor
public protocol SignalTeachByDemoContextResolving: AnyObject {
    func isApplicationReviewed(
        _ application: SignalTeachByDemoApplication
    ) -> Bool
    func target(
        at point: SignalTeachByDemoScreenPoint,
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget?
    func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget?
    func reviewedHTTPSURL(
        for application: SignalTeachByDemoApplication
    ) -> String?
}

@MainActor
public protocol SignalTeachByDemoCaptureScheduling: AnyObject {
    func startRepeating(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    )
    func stop()
}

@MainActor
public protocol SignalTeachByDemoCaptureClock: AnyObject {
    var now: TimeInterval { get }
}

/// Optional local preview seam. Implementations must display transient local
/// content only; the interface has no upload, persistence, or frame-export API.
@MainActor
public protocol SignalTeachByDemoLocalPreviewing: AnyObject {
    func startLocalPreview() throws
    func stopLocalPreview()
}

@MainActor
public protocol SignalTeachByDemoCaptureProposalReceiving: AnyObject {
    func beginCapture()
    func finishCaptureForReview() throws
    func cancel()
    func recordOpenHTTPSURL(_ rawURL: String) throws
    func recordAccessibilityClick(
        target: SignalReviewedAccessibilityTarget
    ) throws
    func recordTypedText(
        _ text: String,
        target: SignalReviewedAccessibilityTarget,
        isSecret: Bool
    ) throws
    func recordKeyCombo(_ combo: SignalTeachByDemoKeyCombo) throws
    func recordWait(milliseconds: Int) throws
    func recordSecureInputRedaction(applicationBundleIdentifier: String)
}

extension SignalTeachByDemoModel:
    SignalTeachByDemoCaptureProposalReceiving
{
    public func recordSecureInputRedaction(
        applicationBundleIdentifier: String
    ) {
        let secureTarget = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: applicationBundleIdentifier,
            role: "AXSecureTextField",
            title: "Secure field",
            isSecureField: true,
            wasUserReviewed: true
        )
        try? recordTypedText(
            "",
            target: secureTarget,
            isSecret: true
        )
    }
}

public enum SignalTeachByDemoCaptureStopReason: Equatable, Sendable {
    case userStopped
    case durationLimit
    case userCancelled
    case emergency
    case startFailed
}

public enum SignalTeachByDemoCapturePhase: Equatable, Sendable {
    case idle
    case recording
    case stopped
    case cancelled
    case failed(String)
}

public struct SignalTeachByDemoCaptureVisibleState:
    Equatable,
    Sendable
{
    public var phase: SignalTeachByDemoCapturePhase
    public var elapsed: TimeInterval
    public var recommendedDuration: TimeInterval
    public var hardDurationLimit: TimeInterval
    public var hasReachedRecommendedDuration: Bool
    public var redactionCount: Int
    public var stopReason: SignalTeachByDemoCaptureStopReason?

    public init(
        phase: SignalTeachByDemoCapturePhase,
        elapsed: TimeInterval,
        recommendedDuration: TimeInterval,
        hardDurationLimit: TimeInterval,
        hasReachedRecommendedDuration: Bool,
        redactionCount: Int,
        stopReason: SignalTeachByDemoCaptureStopReason?
    ) {
        self.phase = phase
        self.elapsed = elapsed
        self.recommendedDuration = recommendedDuration
        self.hardDurationLimit = hardDurationLimit
        self.hasReachedRecommendedDuration = hasReachedRecommendedDuration
        self.redactionCount = redactionCount
        self.stopReason = stopReason
    }
}

public enum SignalTeachByDemoCaptureError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case alreadyRecording
    case notRecording
    case reviewContextRequired
    case eventTapUnavailable
    case localPreviewUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Teach by Demo capture is already recording."
        case .notRecording:
            "Teach by Demo capture is not recording."
        case .reviewContextRequired:
            "A reviewed active application or accessibility target is required."
        case .eventTapUnavailable:
            "The local input event tap could not be created."
        case .localPreviewUnavailable(let reason):
            "The local preview could not start: \(reason)"
        }
    }
}

@MainActor
public final class SignalTeachByDemoCaptureAdapter {
    public static let recommendedDuration: TimeInterval = 30
    public static let hardDurationLimit: TimeInterval = 60

    public var onVisibleStateChange:
        (@MainActor (SignalTeachByDemoCaptureVisibleState) -> Void)?

    public private(set) var visibleState: SignalTeachByDemoCaptureVisibleState

    private let eventCapture: any SignalTeachByDemoEventCapturing
    private let applicationObserver: any SignalTeachByDemoApplicationObserving
    private let contextResolver: any SignalTeachByDemoContextResolving
    private let scheduler: any SignalTeachByDemoCaptureScheduling
    private let clock: any SignalTeachByDemoCaptureClock
    private let preview: any SignalTeachByDemoLocalPreviewing
    private let proposals: any SignalTeachByDemoCaptureProposalReceiving
    private let safetyPolicy: SignalCustomCommandSafetyPolicy

    private var startedAt: TimeInterval?
    private var activeApplication: SignalTeachByDemoApplication?

    public init(
        eventCapture: any SignalTeachByDemoEventCapturing,
        applicationObserver: any SignalTeachByDemoApplicationObserving,
        contextResolver: any SignalTeachByDemoContextResolving,
        scheduler: any SignalTeachByDemoCaptureScheduling,
        clock: any SignalTeachByDemoCaptureClock,
        preview: any SignalTeachByDemoLocalPreviewing,
        proposals: any SignalTeachByDemoCaptureProposalReceiving,
        safetyPolicy: SignalCustomCommandSafetyPolicy = .init()
    ) {
        self.eventCapture = eventCapture
        self.applicationObserver = applicationObserver
        self.contextResolver = contextResolver
        self.scheduler = scheduler
        self.clock = clock
        self.preview = preview
        self.proposals = proposals
        self.safetyPolicy = safetyPolicy
        visibleState = Self.makeState(
            phase: .idle,
            elapsed: 0,
            redactionCount: 0,
            stopReason: nil
        )
    }

    public var isRecording: Bool {
        visibleState.phase == .recording
    }

    /// Capture starts only through this explicit user-initiated entry point.
    /// Construction and callbacks never start it automatically.
    public func start() throws {
        guard !isRecording else {
            throw SignalTeachByDemoCaptureError.alreadyRecording
        }

        proposals.beginCapture()
        startedAt = finiteNow
        activeApplication = applicationObserver.frontmostApplication
        visibleState = Self.makeState(
            phase: .recording,
            elapsed: 0,
            redactionCount: 0,
            stopReason: nil
        )

        do {
            try preview.startLocalPreview()
            applicationObserver.start { [weak self] application in
                self?.handleApplicationActivation(application)
            }
            try eventCapture.start { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleCapturedEvent(event)
                }
            }
            scheduler.startRepeating(interval: 0.25) { [weak self] in
                self?.updateElapsedTime()
            }
            publishVisibleState()
        } catch {
            tearDownSources()
            proposals.cancel()
            startedAt = nil
            activeApplication = nil
            visibleState = Self.makeState(
                phase: .failed(error.localizedDescription),
                elapsed: 0,
                redactionCount: 0,
                stopReason: .startFailed
            )
            publishVisibleState()
            throw error
        }
    }

    public func stop() throws {
        try stopForReview(reason: .userStopped)
    }

    public func cancel() {
        cancel(reason: .userCancelled)
    }

    /// Immediate seam for the app's existing emergency-stop path.
    public func emergencyCancel() {
        cancel(reason: .emergency)
    }

    public func recordReviewedWait(milliseconds: Int) throws {
        guard isRecording else {
            throw SignalTeachByDemoCaptureError.notRecording
        }
        guard let activeApplication,
              contextResolver.isApplicationReviewed(activeApplication) else {
            throw SignalTeachByDemoCaptureError.reviewContextRequired
        }
        try proposals.recordWait(milliseconds: milliseconds)
    }

    private func handleApplicationActivation(
        _ application: SignalTeachByDemoApplication
    ) {
        guard isRecording else { return }
        activeApplication = application
        guard contextResolver.isApplicationReviewed(application),
              let reviewedURL = contextResolver.reviewedHTTPSURL(
                  for: application
              ) else {
            return
        }
        try? proposals.recordOpenHTTPSURL(reviewedURL)
    }

    private func handleCapturedEvent(
        _ event: SignalTeachByDemoCapturedEvent
    ) {
        guard isRecording,
              let application = activeApplication,
              contextResolver.isApplicationReviewed(application) else {
            return
        }

        switch event {
        case .secureKeyboardInput:
            recordRedaction(for: application)
        case .primaryPointerReleased(let point):
            guard let resolved = contextResolver.target(
                at: point,
                in: application
            ) else {
                return
            }
            guard !resolved.target.isSecureField else {
                recordRedaction(for: application)
                return
            }
            guard resolved.isReviewed else { return }
            var target = resolved.target
            target.wasUserReviewed = true
            try? proposals.recordAccessibilityClick(target: target)
        case .keyDown(_, let text, let modifiers, let isRepeat):
            guard !isRepeat,
                  let resolved = contextResolver.focusedTarget(
                      in: application
                  ) else {
                return
            }
            guard !resolved.target.isSecureField else {
                recordRedaction(for: application)
                return
            }
            guard resolved.isReviewed else { return }
            var target = resolved.target
            target.wasUserReviewed = true

            let isPlainText = !modifiers.contains(.command)
                && !modifiers.contains(.control)
                && !modifiers.contains(.option)
                && !modifiers.contains(.function)
                && text?.isEmpty == false
            if isPlainText, let text {
                if safetyPolicy.looksSensitive(text) {
                    recordRedaction(for: application)
                    return
                }
                do {
                    try proposals.recordTypedText(
                        text,
                        target: target,
                        isSecret: false
                    )
                } catch SignalTeachByDemoError.secureValueRedacted {
                    recordVisibleRedactionOnly()
                } catch {
                    // Invalid or prohibited text is omitted, never downgraded
                    // into a raw key event.
                }
            } else {
                let key = text?.isEmpty == false
                    ? text!
                    : "keyCode-\(event.keyCode ?? -1)"
                try? proposals.recordKeyCombo(
                    .init(key: key, modifiers: modifiers)
                )
            }
        }
    }

    private func recordRedaction(
        for application: SignalTeachByDemoApplication
    ) {
        proposals.recordSecureInputRedaction(
            applicationBundleIdentifier: application.bundleIdentifier
        )
        visibleState.redactionCount += 1
        publishVisibleState()
    }

    private func recordVisibleRedactionOnly() {
        visibleState.redactionCount += 1
        publishVisibleState()
    }

    private func updateElapsedTime() {
        guard isRecording, let startedAt else { return }
        let elapsed = max(0, finiteNow - startedAt)
        visibleState = Self.makeState(
            phase: .recording,
            elapsed: min(elapsed, Self.hardDurationLimit),
            redactionCount: visibleState.redactionCount,
            stopReason: nil
        )
        publishVisibleState()

        if elapsed >= Self.hardDurationLimit {
            try? stopForReview(reason: .durationLimit)
        }
    }

    private func stopForReview(
        reason: SignalTeachByDemoCaptureStopReason
    ) throws {
        guard isRecording else {
            throw SignalTeachByDemoCaptureError.notRecording
        }
        let elapsed = currentElapsed
        tearDownSources()
        do {
            try proposals.finishCaptureForReview()
            visibleState = Self.makeState(
                phase: .stopped,
                elapsed: elapsed,
                redactionCount: visibleState.redactionCount,
                stopReason: reason
            )
        } catch {
            proposals.cancel()
            visibleState = Self.makeState(
                phase: .failed(error.localizedDescription),
                elapsed: elapsed,
                redactionCount: visibleState.redactionCount,
                stopReason: reason
            )
            publishVisibleState()
            throw error
        }
        startedAt = nil
        activeApplication = nil
        publishVisibleState()
    }

    private func cancel(reason: SignalTeachByDemoCaptureStopReason) {
        guard isRecording else { return }
        let elapsed = currentElapsed
        tearDownSources()
        proposals.cancel()
        startedAt = nil
        activeApplication = nil
        visibleState = Self.makeState(
            phase: .cancelled,
            elapsed: elapsed,
            redactionCount: visibleState.redactionCount,
            stopReason: reason
        )
        publishVisibleState()
    }

    private func tearDownSources() {
        scheduler.stop()
        eventCapture.stop()
        applicationObserver.stop()
        preview.stopLocalPreview()
    }

    private var finiteNow: TimeInterval {
        clock.now.isFinite ? clock.now : 0
    }

    private var currentElapsed: TimeInterval {
        guard let startedAt else { return visibleState.elapsed }
        return min(
            max(0, finiteNow - startedAt),
            Self.hardDurationLimit
        )
    }

    private func publishVisibleState() {
        onVisibleStateChange?(visibleState)
    }

    private static func makeState(
        phase: SignalTeachByDemoCapturePhase,
        elapsed: TimeInterval,
        redactionCount: Int,
        stopReason: SignalTeachByDemoCaptureStopReason?
    ) -> SignalTeachByDemoCaptureVisibleState {
        SignalTeachByDemoCaptureVisibleState(
            phase: phase,
            elapsed: elapsed,
            recommendedDuration: recommendedDuration,
            hardDurationLimit: hardDurationLimit,
            hasReachedRecommendedDuration: elapsed >= recommendedDuration,
            redactionCount: redactionCount,
            stopReason: stopReason
        )
    }
}

private extension SignalTeachByDemoCapturedEvent {
    var keyCode: Int64? {
        if case .keyDown(let keyCode, _, _, _) = self {
            return keyCode
        }
        return nil
    }
}
