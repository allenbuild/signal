import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalCommandCoordinatorIntegrationTests: XCTestCase {
    func testTriggeredDefaultExecutesPersistedPlanExactlyOnceAndHeldEventsDoNotRepeat()
        async throws {
        let harness = makeHarness()
        defer { harness.removeTemporaryFiles() }
        harness.coordinator.setMode(.commands)

        let document = try await harness.repository.loadOrInstallDefaults()
        let command = try XCTUnwrap(document.profile[.one])
        let expectedAction = try XCTUnwrap(command.plan?.steps.first?.action)
        let match = makeMatch(.one)

        harness.coordinator.handleCommandRecognition(
            .triggered(timestamp: .init(rawValue: 1), match: match)
        )
        try await waitFor(
            performer: harness.performer,
            committedEffects: 1
        )

        for timestamp in [1.1, 1.2, 4.0] {
            harness.coordinator.handleCommandRecognition(
                .waitingForRelease(
                    timestamp: .init(rawValue: timestamp),
                    match: match
                )
            )
        }
        harness.coordinator.handleCommandRecognition(
            .progressing(
                timestamp: .init(rawValue: 4.1),
                match: match,
                progress: 0.75
            )
        )
        try await settle()

        let attemptedActions = await harness.performer.attemptedActions()
        let committedActions = await harness.performer.committedActions()
        let persistedDocument = try await harness.repository.load()
        XCTAssertEqual(attemptedActions, [expectedAction])
        XCTAssertEqual(committedActions, [expectedAction])
        XCTAssertEqual(persistedDocument, document)
        XCTAssertEqual(match.cardID, .one)
        XCTAssertEqual(command.name, "Rickroll")
    }

    func testPausedAndControlModesIgnoreTriggeredCommands() async throws {
        let harness = makeHarness()
        defer { harness.removeTemporaryFiles() }
        let event = SignalCommandRecognitionEvent.triggered(
            timestamp: .init(rawValue: 1),
            match: makeMatch(.one)
        )

        XCTAssertEqual(harness.state.mode, .paused)
        harness.coordinator.handleCommandRecognition(event)
        try await settle()
        let pausedAttempts = await harness.performer.attemptedActions()
        XCTAssertEqual(pausedAttempts, [])

        harness.coordinator.setMode(.control)
        XCTAssertEqual(harness.state.mode, .control)
        harness.coordinator.handleCommandRecognition(event)
        try await settle()

        let controlAttempts = await harness.performer.attemptedActions()
        let committedActions = await harness.performer.committedActions()
        XCTAssertEqual(controlAttempts, [])
        XCTAssertEqual(committedActions, [])
    }

    func testModeSwitchCancelsPendingExecutionBeforeItsEffectCommits() async throws {
        let harness = makeHarness(behavior: .waitForCancellation)
        defer { harness.removeTemporaryFiles() }
        harness.coordinator.setMode(.commands)
        harness.coordinator.handleCommandRecognition(
            .triggered(
                timestamp: .init(rawValue: 1),
                match: makeMatch(.one)
            )
        )
        try await waitFor(performer: harness.performer, attempts: 1)

        harness.coordinator.setMode(.control)

        try await waitFor(performer: harness.performer, cancellations: 1)
        let attempts = await harness.performer.attemptedActions()
        let committedActions = await harness.performer.committedActions()
        XCTAssertEqual(harness.state.mode, .control)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(committedActions, [])
    }

    func testEmergencyStopCancelsPendingExecutionBeforeItsEffectCommits() async throws {
        let harness = makeHarness(behavior: .waitForCancellation)
        defer { harness.removeTemporaryFiles() }
        harness.coordinator.setMode(.commands)
        harness.coordinator.handleCommandRecognition(
            .triggered(
                timestamp: .init(rawValue: 1),
                match: makeMatch(.one)
            )
        )
        try await waitFor(performer: harness.performer, attempts: 1)

        harness.coordinator.emergencyStop()

        try await waitFor(performer: harness.performer, cancellations: 1)
        let attempts = await harness.performer.attemptedActions()
        let committedActions = await harness.performer.committedActions()
        XCTAssertEqual(harness.state.mode, .paused)
        XCTAssertEqual(harness.state.status, .emergencyStopped)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(committedActions, [])
    }

    func testUnconfiguredFistFailsClosedWithoutCallingPerformer() async throws {
        let harness = makeHarness()
        defer { harness.removeTemporaryFiles() }
        harness.coordinator.setMode(.commands)

        harness.coordinator.handleCommandRecognition(
            .triggered(
                timestamp: .init(rawValue: 1),
                match: makeMatch(.fist)
            )
        )
        try await waitForRepositoryDocument(harness)
        try await settle()

        let document = try await harness.repository.load()
        let fist = try XCTUnwrap(document.profile[.fist])
        let attemptedActions = await harness.performer.attemptedActions()
        let committedActions = await harness.performer.committedActions()
        XCTAssertTrue(fist.isConfigurable)
        XCTAssertNil(fist.plan)
        XCTAssertEqual(attemptedActions, [])
        XCTAssertEqual(committedActions, [])
    }

    func testDocumentUpdatesOnlyFistCardAndReportsItsConfigurationTruthfully()
        throws {
        let fixedCardCount = SignalDashboardCardID.allCases.count - 1
        let fixedCards = Array(
            SignalDashboardCommandCard.canonical.prefix(fixedCardCount)
        )
        let defaults = SignalDefaultCommandCatalog.document
        let fixedDefinitions = Array(
            defaults.profile.commands.prefix(fixedCardCount)
        )

        XCTAssertEqual(fixedCards.map(\.commandName), fixedDefinitions.map(\.name))
        XCTAssertTrue(fixedDefinitions.allSatisfy { !$0.isConfigurable })
        XCTAssertTrue(fixedDefinitions.allSatisfy { $0.plan != nil })

        let model = SignalUIModel()
        model.updateCommandDocument(defaults)
        XCTAssertEqual(
            Array(model.dashboardPresentation.cards.prefix(fixedCardCount)),
            fixedCards
        )
        XCTAssertEqual(
            model.dashboardPresentation.cards.last?.commandName,
            "Custom Command"
        )
        XCTAssertEqual(
            model.dashboardPresentation.cards.last?.isConfigured,
            false
        )

        var configured = defaults
        let fistIndex = try XCTUnwrap(
            configured.profile.commands.firstIndex { $0.gesture == .fist }
        )
        configured.profile.commands[fistIndex].name = "Reviewed Fist URL"
        configured.profile.commands[fistIndex].plan = SignalCommandPlan(
            id: "signal.test.fist.plan",
            steps: [
                SignalCommandStep(
                    id: "signal.test.fist.step",
                    action: .openURL(.init(url: "https://example.com/signal"))
                )
            ]
        )
        model.updateCommandDocument(configured)

        XCTAssertEqual(
            Array(model.dashboardPresentation.cards.prefix(fixedCardCount)),
            fixedCards
        )
        XCTAssertEqual(
            model.dashboardPresentation.cards.last?.commandName,
            "Reviewed Fist URL"
        )
        XCTAssertEqual(
            model.dashboardPresentation.cards.last?.isConfigured,
            true
        )
    }

    private func makeHarness(
        behavior: CoordinatorCommandPerformerFake.Behavior = .succeed
    ) -> CoordinatorCommandHarness {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SignalCommandCoordinatorIntegrationTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let repository = SignalCommandRepository(
            directory: temporaryRoot.appendingPathComponent(
                "Commands",
                isDirectory: true
            )
        )
        let performer = CoordinatorCommandPerformerFake(behavior: behavior)
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: true
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: true,
                localMonitorInstalled: true
            ),
            commandRecognitionRuntime: SignalCommandRecognitionRuntime(),
            commandRepository: repository,
            commandExecutor: SignalCommandExecutor(),
            commandPerformer: performer
        )
        return CoordinatorCommandHarness(
            temporaryRoot: temporaryRoot,
            state: state,
            repository: repository,
            performer: performer,
            coordinator: coordinator
        )
    }

    private func makeMatch(
        _ sourceGesture: CommandGesture
    ) -> SignalCommandRecognitionMatch {
        let identity = SignalCommandRecognitionRuntime.identity(
            for: sourceGesture
        )
        return SignalCommandRecognitionMatch(
            sourceGesture: sourceGesture,
            commandGesture: identity.commandGesture,
            cardID: identity.cardID,
            confidence: 0.99,
            requiredJointConfidence: 0.99
        )
    }

    private func waitFor(
        performer: CoordinatorCommandPerformerFake,
        attempts expected: Int
    ) async throws {
        try await waitUntil("performer attempt count \(expected)") {
            await performer.attemptedActions().count == expected
        }
    }

    private func waitFor(
        performer: CoordinatorCommandPerformerFake,
        committedEffects expected: Int
    ) async throws {
        try await waitUntil("committed effect count \(expected)") {
            await performer.committedActions().count == expected
        }
    }

    private func waitFor(
        performer: CoordinatorCommandPerformerFake,
        cancellations expected: Int
    ) async throws {
        try await waitUntil("performer cancellation count \(expected)") {
            await performer.cancellationCount() == expected
        }
    }

    private func waitForRepositoryDocument(
        _ harness: CoordinatorCommandHarness
    ) async throws {
        let documentURL = harness.temporaryRoot
            .appendingPathComponent("Commands", isDirectory: true)
            .appendingPathComponent(
                SignalCommandRepository.activeFilename,
                isDirectory: false
            )
        try await waitUntil("default command document") {
            FileManager.default.fileExists(atPath: documentURL.path)
        }
    }

    private func waitUntil(
        _ description: String,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for \(description).")
                return
            }
            try await ContinuousClock().sleep(for: .milliseconds(5))
        }
    }

    private func settle() async throws {
        try await ContinuousClock().sleep(for: .milliseconds(30))
    }
}

@MainActor
private struct CoordinatorCommandHarness {
    let temporaryRoot: URL
    let state: AppState
    let repository: SignalCommandRepository
    let performer: CoordinatorCommandPerformerFake
    let coordinator: AppCoordinator

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}

private actor CoordinatorCommandPerformerFake:
    SignalCommandActionPerforming {
    enum Behavior: Sendable {
        case succeed
        case waitForCancellation
    }

    private let behavior: Behavior
    private var attempts: [SignalCommandAction] = []
    private var committedEffects: [SignalCommandAction] = []
    private var cancellations = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func perform(
        _ action: SignalCommandAction,
        context: SignalCommandExecutionContext
    ) async throws -> String {
        try context.checkCancellation()
        attempts.append(action)

        switch behavior {
        case .succeed:
            try context.checkCancellation()
            committedEffects.append(action)
            return "fake effect committed"
        case .waitForCancellation:
            do {
                try await ContinuousClock().sleep(for: .seconds(30))
                try context.checkCancellation()
                committedEffects.append(action)
                return "unexpected fake effect"
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }
    }

    func attemptedActions() -> [SignalCommandAction] {
        attempts
    }

    func committedActions() -> [SignalCommandAction] {
        committedEffects
    }

    func cancellationCount() -> Int {
        cancellations
    }
}
