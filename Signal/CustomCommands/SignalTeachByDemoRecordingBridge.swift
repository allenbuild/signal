import Foundation

@MainActor
public protocol SignalTeachByDemoCaptureCoordinating: AnyObject {
    var onVisibleStateChange:
        (@MainActor (SignalTeachByDemoCaptureVisibleState) -> Void)? {
        get set
    }
    var visibleState: SignalTeachByDemoCaptureVisibleState { get }
    var isRecording: Bool { get }

    func start() throws
    func stop() throws
    func cancel()
    func emergencyCancel()
}

extension SignalTeachByDemoCaptureAdapter:
    SignalTeachByDemoCaptureCoordinating
{}

@MainActor
public final class SignalTeachByDemoRecordingBridge: ObservableObject {
    @Published public private(set) var captureState:
        SignalTeachByDemoCaptureVisibleState
    @Published public private(set) var errorMessage: String?

    public let proposalModel: SignalTeachByDemoModel

    private let capture: any SignalTeachByDemoCaptureCoordinating
    private let canStart: @MainActor () -> Bool

    public init(
        proposalModel: SignalTeachByDemoModel,
        capture: any SignalTeachByDemoCaptureCoordinating,
        canStart: @escaping @MainActor () -> Bool = { true }
    ) {
        self.proposalModel = proposalModel
        self.capture = capture
        self.canStart = canStart
        captureState = capture.visibleState
        capture.onVisibleStateChange = { [weak self] state in
            self?.captureState = state
            if case .failed(let message) = state.phase {
                self?.errorMessage = message
            }
        }
    }

    /// Convenience initializer for the real local-only capture stack.
    /// Construction remains inert; `start()` is still required explicitly.
    public convenience init(
        proposalModel: SignalTeachByDemoModel,
        reviewContext: SignalTeachByDemoReviewContext,
        ignoredEventMarker: Int64? = nil,
        preview: (any SignalTeachByDemoLocalPreviewing)? = nil,
        canStart: @escaping @MainActor () -> Bool = { true }
    ) {
        let capture = SignalTeachByDemoCaptureAdapter(
            eventCapture: SignalTeachByDemoCGEventTap(
                ignoredEventMarker: ignoredEventMarker
            ),
            applicationObserver: SignalTeachByDemoWorkspaceObserver(),
            contextResolver: SignalTeachByDemoAXContextResolver(
                reviewContext: reviewContext
            ),
            scheduler: SignalTeachByDemoTimerScheduler(),
            clock: SignalTeachByDemoSystemClock(),
            preview: preview ?? SignalTeachByDemoDisabledLocalPreview(),
            proposals: proposalModel
        )
        self.init(
            proposalModel: proposalModel,
            capture: capture,
            canStart: canStart
        )
    }

    public var isRecording: Bool {
        captureState.phase == .recording
    }

    public var elapsed: TimeInterval {
        captureState.elapsed
    }

    public var recommendedDuration: TimeInterval {
        captureState.recommendedDuration
    }

    public var hardDurationLimit: TimeInterval {
        captureState.hardDurationLimit
    }

    public var hasReachedRecommendedDuration: Bool {
        captureState.hasReachedRecommendedDuration
    }

    public var redactionCount: Int {
        captureState.redactionCount
    }

    public var proposals: [SignalTeachByDemoProposal] {
        proposalModel.proposals
    }

    public var canUseReviewedSteps: Bool {
        proposalModel.canApplyToRuntime
    }

    public func start() {
        errorMessage = nil
        guard canStart() else {
            errorMessage = """
                Accessibility and the global Emergency Stop shortcut are \
                required before recording.
                """
            return
        }
        do {
            try capture.start()
            captureState = capture.visibleState
        } catch {
            captureState = capture.visibleState
            errorMessage = error.localizedDescription
        }
    }

    public func stop() {
        errorMessage = nil
        do {
            try capture.stop()
            captureState = capture.visibleState
        } catch {
            captureState = capture.visibleState
            errorMessage = error.localizedDescription
        }
    }

    public func cancel() {
        errorMessage = nil
        capture.cancel()
        captureState = capture.visibleState
    }

    public func emergencyCancel() {
        errorMessage = nil
        capture.emergencyCancel()
        captureState = capture.visibleState
    }

    public func setReviewed(
        _ reviewed: Bool,
        proposalID: String
    ) {
        do {
            try proposalModel.setReviewed(
                reviewed,
                proposalID: proposalID
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteProposal(id: String) {
        proposalModel.deleteProposal(id: id)
        errorMessage = nil
    }

    public func moveProposal(id: String, to destinationIndex: Int) {
        do {
            try proposalModel.moveProposal(
                id: id,
                to: destinationIndex
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reviewedRuntimeSteps()
        -> [SignalCustomCommandStepDraft]?
    {
        do {
            let steps = try proposalModel.reviewedRuntimeSteps()
            errorMessage = nil
            return steps
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func clearError() {
        errorMessage = nil
    }
}
