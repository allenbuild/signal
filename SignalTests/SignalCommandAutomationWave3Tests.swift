import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalCommandAutomationWave3Tests: XCTestCase {
    func testExecutorRunsEveryStepExactlyOnce() async throws {
        let performer = SignalCommandPerformerFake(behaviors: [.success, .success])
        let executor = SignalCommandExecutor()
        let plan = twoStepPlan()

        let receipt = await executor.execute(plan, performer: performer)
        let performedKinds = await performer.performedKinds()
        let isRunning = await executor.isRunning

        XCTAssertEqual(receipt.status, .success)
        XCTAssertEqual(receipt.stepReceipts.map(\.status), [.success, .success])
        XCTAssertEqual(performedKinds, [.openURL, .spotifyNextTrack])
        XCTAssertFalse(isRunning)
    }

    func testExecutorRejectsConcurrentRunAndCancellationStopsActiveRun() async throws {
        let performer = SignalCommandPerformerFake(
            behaviors: [.sleep(milliseconds: 2_000)]
        )
        let executor = SignalCommandExecutor()
        let plan = SignalCommandPlan(
            id: "signal.test.long-running",
            steps: [
                SignalCommandStep(
                    id: "signal.test.long-running.step",
                    action: .openURL(.init(url: "https://example.com")),
                    timeoutMilliseconds: 5_000
                )
            ],
            timeoutMilliseconds: 6_000
        )

        let first = Task {
            await executor.execute(plan, performer: performer)
        }
        try await waitUntilCallCount(1, performer: performer)

        let second = await executor.execute(plan, performer: performer)
        XCTAssertEqual(second.status, .rejectedAlreadyRunning)

        await executor.cancel()
        let cancelled = await first.value
        let performedCount = await performer.performedKinds().count
        let isRunning = await executor.isRunning
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(performedCount, 1)
        XCTAssertFalse(isRunning)
    }

    func testStepTimeoutCancelsPerformerAndReturnsTruthfulReceipt() async {
        let performer = SignalCommandPerformerFake(
            behaviors: [.sleep(milliseconds: 1_000)]
        )
        let executor = SignalCommandExecutor()
        let plan = SignalCommandPlan(
            id: "signal.test.timeout",
            steps: [
                SignalCommandStep(
                    id: "signal.test.timeout.step",
                    action: .spotifyNextTrack(.init()),
                    timeoutMilliseconds: 100
                )
            ],
            timeoutMilliseconds: 1_000
        )

        let receipt = await executor.execute(plan, performer: performer)
        let cancellationCount = await performer.cancellationCount()

        XCTAssertEqual(receipt.status, .timedOut)
        XCTAssertEqual(receipt.stepReceipts.map(\.status), [.timedOut])
        XCTAssertEqual(cancellationCount, 1)
    }

    func testContinuePolicyRunsNextStepAfterFailure() async {
        let performer = SignalCommandPerformerFake(behaviors: [.failure, .success])
        let executor = SignalCommandExecutor()
        var plan = twoStepPlan()
        plan.steps[0].failurePolicy = .continue

        let receipt = await executor.execute(plan, performer: performer)
        let performedKinds = await performer.performedKinds()

        XCTAssertEqual(receipt.status, .failure)
        XCTAssertEqual(receipt.stepReceipts.map(\.status), [.failure, .success])
        XCTAssertEqual(performedKinds, [.openURL, .spotifyNextTrack])
    }

    func testInvalidPlanNeverReachesPerformer() async {
        let performer = SignalCommandPerformerFake(behaviors: [.success])
        let executor = SignalCommandExecutor()
        let plan = SignalCommandPlan(
            id: "signal.test.invalid",
            steps: [
                SignalCommandStep(
                    id: "signal.test.invalid.step",
                    action: .openURL(.init(url: "http://localhost")),
                    timeoutMilliseconds: 1_000
                )
            ]
        )

        let receipt = await executor.execute(plan, performer: performer)
        let performedKinds = await performer.performedKinds()

        XCTAssertEqual(receipt.status, .failure)
        XCTAssertTrue(performedKinds.isEmpty)
    }

    private func twoStepPlan() -> SignalCommandPlan {
        SignalCommandPlan(
            id: "signal.test.two-step",
            steps: [
                SignalCommandStep(
                    id: "signal.test.two-step.open",
                    action: .openURL(.init(url: "https://example.com"))
                ),
                SignalCommandStep(
                    id: "signal.test.two-step.spotify",
                    action: .spotifyNextTrack(.init())
                )
            ]
        )
    }

    private func waitUntilCallCount(
        _ expected: Int,
        performer: SignalCommandPerformerFake
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await performer.performedKinds().count < expected {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for fake performer.")
                return
            }
            try await ContinuousClock().sleep(for: .milliseconds(5))
        }
    }
}

private actor SignalCommandPerformerFake: SignalCommandActionPerforming {
    enum Behavior: Sendable {
        case success
        case failure
        case sleep(milliseconds: Int)
    }

    private var behaviors: [Behavior]
    private var calls: [SignalCommandAction.Kind] = []
    private var cancellations = 0

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    func perform(
        _ action: SignalCommandAction,
        context: SignalCommandExecutionContext
    ) async throws -> String {
        try context.checkCancellation()
        calls.append(action.kind)
        let behavior = behaviors.isEmpty ? .success : behaviors.removeFirst()
        switch behavior {
        case .success:
            try context.checkCancellation()
            return "ok"
        case .failure:
            throw SignalCommandPerformerFakeError.expectedFailure
        case .sleep(let milliseconds):
            do {
                try await ContinuousClock().sleep(for: .milliseconds(milliseconds))
                try context.checkCancellation()
                return "slept"
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }
    }

    func performedKinds() -> [SignalCommandAction.Kind] {
        calls
    }

    func cancellationCount() -> Int {
        cancellations
    }
}

private enum SignalCommandPerformerFakeError: Error, Sendable {
    case expectedFailure
}
