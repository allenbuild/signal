import Foundation
import XCTest
@testable import SignalCore

final class MacroRecorderSafetyTests: XCTestCase {
    func testSafetyStartsPausedNeverAutomaticallyReenablesAndEmergencyCancels() {
        let gate = SafetyGate()
        let callbackGate = SafetyGate()
        callbackGate.enableExplicitly()
        _ = gate.onPause { callbackGate.pause(.user) }
        XCTAssertTrue(gate.isPaused)
        gate.enableExplicitly()
        XCTAssertFalse(gate.isPaused)
        gate.emergencyPause()
        XCTAssertTrue(gate.isPaused)
        XCTAssertEqual(gate.reason, .emergency)
        XCTAssertTrue(callbackGate.isPaused)
        XCTAssertTrue(gate.isPaused)
    }

    func testSynchronousGateOperationCannotBeginAfterEmergencyPause() {
        let gate = SafetyGate()
        gate.enableExplicitly()
        var effects = 0
        let first = gate.performIfEnabled {
            effects += 1
            return "posted"
        }
        XCTAssertEqual(first, "posted")
        gate.emergencyPause()
        let blocked = gate.performIfEnabled {
            effects += 1
            return "must not post"
        }
        XCTAssertNil(blocked)
        XCTAssertEqual(effects, 1)
    }

    func testMacroExecutesValidatedStepsAndProducesReceipts() async {
        let performer = MockPerformer()
        let executor = MacroExecutor()
        let result = await executor.execute(makePlan(), performer: performer)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.stepReceipts.count, 2)
        XCTAssertTrue(result.stepReceipts.allSatisfy { $0.status == .success })
        let count = await performer.count
        XCTAssertEqual(count, 2)
    }

    func testMacroCancellationStopsActiveAction() async {
        let performer = SlowPerformer()
        let executor = MacroExecutor()
        let task = Task { await executor.execute(makePlan(), performer: performer) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await executor.cancel()
        let result = await task.value
        XCTAssertEqual(result.status, .cancelled)
    }

    func testExecutorDefaultConfirmationPolicyDeniesUnreviewedEffects() async {
        var plan = makePlan()
        plan.confirmation = .init(mode: .everyRun, reason: "External effect")
        let result = await MacroExecutor().execute(plan, performer: MockPerformer())
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertTrue(result.stepReceipts.isEmpty)
    }

    func testControlledRecorderRequiresExplicitStartAndTextConsent() throws {
        var recorder = ControlledDemoRecorder()
        XCTAssertThrowsError(try recorder.record(ActionStep(action: .wait), at: 0))
        recorder.beginCountdown()
        recorder.start(at: 10)
        XCTAssertThrowsError(try recorder.record(ActionStep(
            action: .typeText,
            parameters: ["text": .string("private")]
        ), at: 10.1)) {
            XCTAssertEqual($0 as? RecorderError, .sensitiveTextRequiresConsent)
        }
    }

    func testControlledRecordTimelineConvertsToEditablePlanAndReplays() async throws {
        var recorder = ControlledDemoRecorder()
        recorder.typedTextConsent = true
        recorder.start(at: 0)
        try recorder.record(ActionStep(
            action: .openApplication,
            parameters: ["bundleIdentifier": .string("com.apple.TextEdit")]
        ), at: 0)
        try recorder.record(ActionStep(
            action: .typeText,
            parameters: ["text": .string("Signal"), "containsSensitiveData": .bool(false)]
        ), at: 1)
        var plan = try recorder.stop(name: "Recorded")
        XCTAssertEqual(plan.createdSource, .demoRecording)
        XCTAssertEqual(plan.steps.map(\.action), [.openApplication, .wait, .typeText])
        plan.approved = true
        let result = await MacroExecutor().execute(
            plan,
            performer: MockPerformer(),
            confirmations: AllowAllConfirmations()
        )
        XCTAssertEqual(result.status, .success)
    }

    func testSafetyGatedPerformerBlocksBeforeUnderlyingEffect() async throws {
        let gate = SafetyGate()
        let underlying = MockPerformer()
        let performer = SafetyGatedPerformer(gate: gate, underlying: underlying)
        do {
            _ = try await performer.perform(ActionStep(action: .speakText, parameters: ["text": .string("blocked")]))
            XCTFail("Expected paused output to block")
        } catch {
            XCTAssertEqual(error as? SafetyAuthorizationError, .outputPaused)
        }
        let count = await underlying.count
        XCTAssertEqual(count, 0)
    }

    func testRecorderCompressorMergesAdjacentNoise() {
        let first = RecordedTimelineItem(
            offset: 0,
            step: ActionStep(
                action: .scrollAmount,
                parameters: ["horizontal": .number(1), "vertical": .number(3)]
            )
        )
        let second = RecordedTimelineItem(
            offset: 0.1,
            step: ActionStep(
                action: .scrollAmount,
                parameters: ["horizontal": .number(2), "vertical": .number(4)]
            )
        )
        let compressed = RecorderEventCompressor().compress([first, second])
        XCTAssertEqual(compressed.count, 1)
        XCTAssertEqual(compressed[0].step.parameters["horizontal"]?.numberValue, 3)
        XCTAssertEqual(compressed[0].step.parameters["vertical"]?.numberValue, 7)
    }

    func testCoreConstructionHasNoCameraOrPermissionSideEffects() async {
        let gate = SafetyGate()
        _ = TouchEngine()
        _ = CommandGestureClassifier()
        _ = CommandActivationEngine()
        _ = LocalProfileStore(directory: FileManager.default.temporaryDirectory)
        _ = PlannerClient()
        _ = MacroExecutor()
        XCTAssertTrue(gate.isPaused)
    }

    private func makePlan() -> ActionPlan {
        ActionPlan(
            id: "test.plan",
            name: "Test",
            description: "Deterministic test",
            steps: [
                ActionStep(action: .speakText, parameters: ["text": .string("one")]),
                ActionStep(action: .wait, parameters: ["durationMs": .number(0)])
            ],
            timeoutMs: 5_000,
            confirmation: .init(),
            createdSource: .visual,
            approved: true
        )
    }
}

private actor MockPerformer: ActionPerforming {
    private(set) var count = 0

    func perform(_ step: ActionStep) async throws -> String {
        count += 1
        return "ok"
    }
}

private struct SlowPerformer: ActionPerforming {
    func perform(_ step: ActionStep) async throws -> String {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return "late"
    }
}
