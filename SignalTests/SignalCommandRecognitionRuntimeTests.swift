import Dispatch
import XCTest
@testable import Signal

final class SignalCommandRecognitionRuntimeTests: XCTestCase {
    func testIdentityMappingIsExactForAllEightGestures() {
        XCTAssertEqual(CommandGesture.allCases.count, 8)
        XCTAssertEqual(SignalCommandGesture.allCases.count, 8)
        XCTAssertEqual(SignalDashboardCardID.allCases.count, 8)
        for gesture in CommandGesture.allCases {
            let identity = SignalCommandRecognitionRuntime.identity(
                for: gesture
            )
            let expected = expectedIdentity(for: gesture)
            XCTAssertEqual(identity.commandGesture, expected.0)
            XCTAssertEqual(identity.cardID, expected.1)
        }
        XCTAssertFalse(CommandGesture.allCases.map(\.rawValue).contains("five"))
    }

    func testUsesCaptureTimestampForProgressAndTriggersOnce() throws {
        let runtime = makeRuntime()
        XCTAssertEqual(
            runtime.setMode(.commands),
            .reset(.modeChanged(from: .paused, to: .commands))
        )

        let first = runtime.process(Self.pointerSnapshot(at: 10))
        let halfway = runtime.process(Self.pointerSnapshot(at: 10.3))
        let trigger = runtime.process(Self.pointerSnapshot(at: 10.6))
        let held = runtime.process(Self.pointerSnapshot(at: 12))

        let firstMatch = try progressingMatch(first, progress: 0)
        XCTAssertEqual(firstMatch.commandGesture, .one)
        XCTAssertEqual(firstMatch.cardID, .one)
        _ = try progressingMatch(halfway, progress: 0.5)

        guard case .triggered(let timestamp, let triggeredMatch) = trigger else {
            return XCTFail("Expected a trigger, got \(trigger)")
        }
        XCTAssertEqual(timestamp.rawValue, 10.6, accuracy: 1e-12)
        XCTAssertEqual(triggeredMatch.commandGesture, .one)
        XCTAssertEqual(triggeredMatch.cardID, .one)

        guard case .waitingForRelease(
            let timestamp,
            let waitingMatch
        ) = held else {
            return XCTFail("Expected release latch, got \(held)")
        }
        XCTAssertEqual(timestamp.rawValue, 12, accuracy: 1e-12)
        XCTAssertEqual(waitingMatch.commandGesture, .one)
    }

    func testPauseAndModeChangesClearPartialActivation() throws {
        let runtime = makeRuntime()
        runtime.setMode(.commands)
        _ = runtime.process(Self.pointerSnapshot(at: 1))
        _ = try progressingMatch(
            runtime.process(Self.pointerSnapshot(at: 1.3)),
            progress: 0.5
        )

        XCTAssertEqual(
            runtime.setMode(.paused),
            .reset(.modeChanged(from: .commands, to: .paused))
        )
        XCTAssertEqual(
            runtime.process(Self.pointerSnapshot(at: 1.6)),
            .reset(.inactiveMode(.paused))
        )
        XCTAssertEqual(
            runtime.setMode(.commands),
            .reset(.modeChanged(from: .paused, to: .commands))
        )
        _ = try progressingMatch(
            runtime.process(Self.pointerSnapshot(at: 2)),
            progress: 0
        )

        XCTAssertEqual(
            runtime.setMode(.control),
            .reset(.modeChanged(from: .commands, to: .control))
        )
        XCTAssertEqual(
            runtime.process(Self.pointerSnapshot(at: 2.6)),
            .reset(.inactiveMode(.control))
        )
    }

    func testTrackingLossAndAmbiguousHandsClearPartialActivation() throws {
        let runtime = makeRuntime()
        runtime.setMode(.commands)
        _ = runtime.process(Self.pointerSnapshot(at: 1))
        _ = try progressingMatch(
            runtime.process(Self.pointerSnapshot(at: 1.3)),
            progress: 0.5
        )

        XCTAssertEqual(
            runtime.process(
                TrackingSnapshot(
                    timestamp: MonotonicTimestamp(rawValue: 1.4),
                    hands: [],
                    quality: .absent,
                    degradationReason: .noHandDetected
                )
            ),
            .reset(.trackingUnavailable(.noHandDetected))
        )
        _ = try progressingMatch(
            runtime.process(Self.pointerSnapshot(at: 2)),
            progress: 0
        )

        let twoHands = [
            SyntheticHand.pose(.pointer).tracked(id: 1, at: 2.1),
            SyntheticHand.pose(.pointer).tracked(id: 2, at: 2.1)
        ]
        XCTAssertEqual(
            runtime.process(
                TrackingSnapshot(
                    timestamp: MonotonicTimestamp(rawValue: 2.1),
                    hands: twoHands,
                    quality: .good
                )
            ),
            .reset(.handSelection(count: 2))
        )
        _ = try progressingMatch(
            runtime.process(Self.pointerSnapshot(at: 3)),
            progress: 0
        )
    }

    func testRetainedMissingTrackDoesNotCreateASecondCurrentHand() throws {
        let runtime = makeRuntime()
        runtime.setMode(.commands)
        let current = SyntheticHand.pose(.pointer).tracked(id: 1, at: 1)
        let retained = SyntheticHand.pose(.pointer).tracked(
            id: 2,
            at: 1,
            missingDuration: 0.1
        )
        let event = runtime.process(
            TrackingSnapshot(
                timestamp: MonotonicTimestamp(rawValue: 1),
                hands: [current, retained],
                quality: .good
            )
        )

        _ = try progressingMatch(event, progress: 0)
    }

    func testUnreliableHandTimestampRegressionAndGenerationChangeReset() {
        let runtime = makeRuntime()
        runtime.setMode(.commands)

        var unreliable = SyntheticHand.pose(.pointer).tracked(id: 9, at: 1)
        unreliable.associationCertain = false
        XCTAssertEqual(
            runtime.process(
                TrackingSnapshot(
                    timestamp: MonotonicTimestamp(rawValue: 1),
                    hands: [unreliable],
                    quality: .good
                )
            ),
            .reset(.unreliableHand(HandTrackID(rawValue: 9)))
        )

        _ = runtime.process(Self.pointerSnapshot(at: 2, generation: 11))
        _ = runtime.process(Self.pointerSnapshot(at: 2.1, generation: 11))
        XCTAssertEqual(
            runtime.process(Self.pointerSnapshot(at: 1.9, generation: 11)),
            .reset(.timestampRegression)
        )
        _ = runtime.process(Self.pointerSnapshot(at: 3, generation: 11))
        XCTAssertEqual(
            runtime.process(Self.pointerSnapshot(at: 4, generation: 12)),
            .reset(.captureGenerationChanged(from: 11, to: 12))
        )
    }

    func testConcurrentCallsRemainSerializedAndValueOnly() {
        let runtime = makeRuntime()
        runtime.setMode(.commands)
        let queue = DispatchQueue(
            label: "SignalCommandRecognitionRuntimeTests",
            attributes: .concurrent
        )
        let group = DispatchGroup()

        for index in 0..<200 {
            group.enter()
            queue.async {
                if index.isMultiple(of: 11) {
                    _ = runtime.reset()
                    _ = runtime.setMode(.commands)
                } else {
                    _ = runtime.process(
                        Self.pointerSnapshot(at: Double(index))
                    )
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(runtime.mode, .commands)
    }

    private func makeRuntime() -> SignalCommandRecognitionRuntime {
        SignalCommandRecognitionRuntime(
            activationConfiguration: .init(
                holdDuration: 0.6,
                cooldownDuration: 0.9,
                confidenceThreshold: 0.62
            )
        )
    }

    private static func pointerSnapshot(
        at time: Double,
        generation: UInt64 = 0
    ) -> TrackingSnapshot {
        TrackingSnapshot(
            captureGeneration: generation,
            timestamp: MonotonicTimestamp(rawValue: time),
            hands: [SyntheticHand.pose(.pointer).tracked(at: time)],
            quality: .good
        )
    }

    private func progressingMatch(
        _ event: SignalCommandRecognitionEvent,
        progress expectedProgress: Double
    ) throws -> SignalCommandRecognitionMatch {
        guard case .progressing(_, let match, let progress) = event else {
            throw RuntimeTestFailure.unexpectedEvent(String(describing: event))
        }
        XCTAssertEqual(progress, expectedProgress, accuracy: 1e-9)
        return match
    }

    private func expectedIdentity(
        for gesture: CommandGesture
    ) -> (SignalCommandGesture, SignalDashboardCardID) {
        switch gesture {
        case .one: (.one, .one)
        case .two: (.two, .two)
        case .three: (.three, .three)
        case .four: (.four, .four)
        case .thumbsUp: (.thumbsUp, .thumbsUp)
        case .thumbsDown: (.thumbsDown, .thumbsDown)
        case .cShape: (.cShape, .cShape)
        case .fist: (.fist, .fist)
        }
    }
}

private enum RuntimeTestFailure: Error {
    case unexpectedEvent(String)
}
