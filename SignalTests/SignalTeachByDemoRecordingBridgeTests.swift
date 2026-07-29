import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalTeachByDemoRecordingBridgeTests: XCTestCase {
    func testConstructionIsInertAndDoesNotStartCapture() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()

        _ = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(capture.stopCount, 0)
        XCTAssertEqual(capture.cancelCount, 0)
        XCTAssertEqual(capture.emergencyCount, 0)
    }

    func testStartAndStopForwardToCaptureAndExposeVisibleState() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        capture.onStart = {
            proposalModel.beginCapture()
        }
        capture.onStop = {
            try? proposalModel.finishCaptureForReview()
        }
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )

        bridge.start()
        capture.publish(
            Self.state(
                phase: .recording,
                elapsed: 31,
                redactions: 2
            )
        )

        XCTAssertTrue(bridge.isRecording)
        XCTAssertEqual(bridge.elapsed, 31)
        XCTAssertTrue(bridge.hasReachedRecommendedDuration)
        XCTAssertEqual(bridge.redactionCount, 2)
        XCTAssertEqual(proposalModel.sessionState, .capturing)

        bridge.stop()
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(proposalModel.sessionState, .reviewing)
    }

    func testCancelAndEmergencyAreSeparateImmediatePaths() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )

        bridge.cancel()
        bridge.emergencyCancel()

        XCTAssertEqual(capture.cancelCount, 1)
        XCTAssertEqual(capture.emergencyCount, 1)
    }

    func testCaptureFailureIsVisibleWithoutThrowingFromUIBridge() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        capture.startError =
            SignalTeachByDemoCaptureError.eventTapUnavailable
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )

        bridge.start()

        XCTAssertEqual(
            bridge.errorMessage,
            SignalTeachByDemoCaptureError.eventTapUnavailable
                .localizedDescription
        )
        XCTAssertFalse(bridge.isRecording)
    }

    func testSafetyPreflightBlocksCaptureBeforeTheEffectBoundary() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture,
            canStart: { false }
        )

        bridge.start()

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertFalse(bridge.isRecording)
        XCTAssertEqual(
            bridge.errorMessage,
            """
            Accessibility and the global Emergency Stop shortcut are \
            required before recording.
            """
        )
    }

    func testReviewOperationsDelegateToProposalModel() throws {
        let proposalModel = SignalTeachByDemoModel(
            makeIdentifier: { "proposal" }
        )
        let capture = FakeRecordingCapture()
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )
        proposalModel.beginCapture()
        try proposalModel.recordOpenHTTPSURL(
            "https://example.com/reviewed"
        )
        try proposalModel.finishCaptureForReview()
        let proposalID = try XCTUnwrap(
            proposalModel.proposals.first?.id
        )

        bridge.setReviewed(true, proposalID: proposalID)

        XCTAssertTrue(proposalModel.proposals.first?.isReviewed == true)
        XCTAssertTrue(bridge.canUseReviewedSteps)
        XCTAssertEqual(
            bridge.reviewedRuntimeSteps()?.first?.action,
            .openHTTPSURL("https://example.com/reviewed")
        )

        bridge.deleteProposal(id: proposalID)
        XCTAssertTrue(proposalModel.proposals.isEmpty)
    }

    func testPanelConstructionInvokesNoCaptureOrUseClosure() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )
        let recorder = UseStepsRecorder()

        _ = SignalTeachByDemoRecordingPanel(
            bridge: bridge,
            useReviewedSteps: { steps in
                recorder.received = steps
            }
        )

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertNil(recorder.received)
    }

    func testBridgeExposesCountsButNoSecretValueChannel() {
        let proposalModel = SignalTeachByDemoModel()
        let capture = FakeRecordingCapture()
        let bridge = SignalTeachByDemoRecordingBridge(
            proposalModel: proposalModel,
            capture: capture
        )

        capture.publish(
            Self.state(
                phase: .recording,
                elapsed: 5,
                redactions: 3
            )
        )

        XCTAssertEqual(bridge.redactionCount, 3)
        XCTAssertTrue(bridge.proposals.isEmpty)
    }

    private static func state(
        phase: SignalTeachByDemoCapturePhase,
        elapsed: TimeInterval,
        redactions: Int
    ) -> SignalTeachByDemoCaptureVisibleState {
        SignalTeachByDemoCaptureVisibleState(
            phase: phase,
            elapsed: elapsed,
            recommendedDuration: 30,
            hardDurationLimit: 60,
            hasReachedRecommendedDuration: elapsed >= 30,
            redactionCount: redactions,
            stopReason: nil
        )
    }
}

@MainActor
private final class FakeRecordingCapture:
    SignalTeachByDemoCaptureCoordinating
{
    var onVisibleStateChange:
        (@MainActor (SignalTeachByDemoCaptureVisibleState) -> Void)?
    private(set) var visibleState =
        SignalTeachByDemoCaptureVisibleState(
            phase: .idle,
            elapsed: 0,
            recommendedDuration: 30,
            hardDurationLimit: 60,
            hasReachedRecommendedDuration: false,
            redactionCount: 0,
            stopReason: nil
        )
    var isRecording: Bool {
        visibleState.phase == .recording
    }

    var startCount = 0
    var stopCount = 0
    var cancelCount = 0
    var emergencyCount = 0
    var startError: Error?
    var onStart: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?

    func start() throws {
        startCount += 1
        if let startError { throw startError }
        onStart?()
        publish(
            SignalTeachByDemoCaptureVisibleState(
                phase: .recording,
                elapsed: 0,
                recommendedDuration: 30,
                hardDurationLimit: 60,
                hasReachedRecommendedDuration: false,
                redactionCount: 0,
                stopReason: nil
            )
        )
    }

    func stop() throws {
        stopCount += 1
        onStop?()
        publish(
            SignalTeachByDemoCaptureVisibleState(
                phase: .stopped,
                elapsed: visibleState.elapsed,
                recommendedDuration: 30,
                hardDurationLimit: 60,
                hasReachedRecommendedDuration:
                    visibleState.hasReachedRecommendedDuration,
                redactionCount: visibleState.redactionCount,
                stopReason: .userStopped
            )
        )
    }

    func cancel() {
        cancelCount += 1
    }

    func emergencyCancel() {
        emergencyCount += 1
    }

    func publish(_ state: SignalTeachByDemoCaptureVisibleState) {
        visibleState = state
        onVisibleStateChange?(state)
    }
}

@MainActor
private final class UseStepsRecorder {
    var received: [SignalCustomCommandStepDraft]?
}
