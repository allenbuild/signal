import Foundation

public struct SignalCommandExecutionContext: Equatable, Sendable {
    public var runID: UUID
    public var planID: String
    public var stepID: String

    public init(runID: UUID, planID: String, stepID: String) {
        self.runID = runID
        self.planID = planID
        self.stepID = stepID
    }

    /// Performers must call this immediately before every externally visible effect.
    public func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

public protocol SignalCommandActionPerforming: Sendable {
    func perform(
        _ action: SignalCommandAction,
        context: SignalCommandExecutionContext
    ) async throws -> String
}

public enum SignalCommandStepStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case timedOut = "timed_out"
}

public enum SignalCommandRunStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case timedOut = "timed_out"
    case rejectedAlreadyRunning = "rejected_already_running"
}

public struct SignalCommandStepReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var stepID: String
    public var actionKind: SignalCommandAction.Kind
    public var status: SignalCommandStepStatus
    public var message: String

    public init(
        id: UUID = UUID(),
        stepID: String,
        actionKind: SignalCommandAction.Kind,
        status: SignalCommandStepStatus,
        message: String
    ) {
        self.id = id
        self.stepID = stepID
        self.actionKind = actionKind
        self.status = status
        self.message = message
    }
}

public struct SignalCommandRunReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var planID: String
    public var status: SignalCommandRunStatus
    public var stepReceipts: [SignalCommandStepReceipt]
    public var message: String
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        id: UUID,
        planID: String,
        status: SignalCommandRunStatus,
        stepReceipts: [SignalCommandStepReceipt],
        message: String,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.id = id
        self.planID = planID
        self.status = status
        self.stepReceipts = stepReceipts
        self.message = message
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

private enum SignalCommandExecutionError: Error {
    case timedOut
}

/// Serial, structured-concurrency executor. A second run is rejected while one is active.
public actor SignalCommandExecutor {
    private let validator: SignalCommandValidator
    private var activeTask: Task<SignalCommandRunReceipt, Never>?

    public init(validator: SignalCommandValidator = .init()) {
        self.validator = validator
    }

    public var isRunning: Bool {
        activeTask != nil
    }

    public func execute(
        _ plan: SignalCommandPlan,
        performer: any SignalCommandActionPerforming
    ) async -> SignalCommandRunReceipt {
        guard activeTask == nil else {
            let now = Date()
            return SignalCommandRunReceipt(
                id: UUID(),
                planID: plan.id,
                status: .rejectedAlreadyRunning,
                stepReceipts: [],
                message: "Another Signal command is already running.",
                startedAt: now,
                finishedAt: now
            )
        }

        let validator = self.validator
        let task = Task {
            await Self.run(plan, validator: validator, performer: performer)
        }
        activeTask = task
        let receipt = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        activeTask = nil
        return receipt
    }

    public func cancel() {
        activeTask?.cancel()
    }

    private static func run(
        _ plan: SignalCommandPlan,
        validator: SignalCommandValidator,
        performer: any SignalCommandActionPerforming
    ) async -> SignalCommandRunReceipt {
        let runID = UUID()
        let startedAt = Date()
        do {
            try validator.validate(plan)
        } catch {
            return SignalCommandRunReceipt(
                id: runID,
                planID: plan.id,
                status: .failure,
                stepReceipts: [],
                message: error.localizedDescription,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }

        do {
            let result = try await withTimeout(milliseconds: plan.timeoutMilliseconds) {
                try await executeSteps(plan, runID: runID, performer: performer)
            }
            return SignalCommandRunReceipt(
                id: runID,
                planID: plan.id,
                status: result.status,
                stepReceipts: result.receipts,
                message: result.message,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return SignalCommandRunReceipt(
                id: runID,
                planID: plan.id,
                status: .cancelled,
                stepReceipts: [],
                message: "Command cancelled.",
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch SignalCommandExecutionError.timedOut {
            return SignalCommandRunReceipt(
                id: runID,
                planID: plan.id,
                status: .timedOut,
                stepReceipts: [],
                message: "Whole-command timeout exceeded.",
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return SignalCommandRunReceipt(
                id: runID,
                planID: plan.id,
                status: .failure,
                stepReceipts: [],
                message: error.localizedDescription,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    private static func executeSteps(
        _ plan: SignalCommandPlan,
        runID: UUID,
        performer: any SignalCommandActionPerforming
    ) async throws -> (
        status: SignalCommandRunStatus,
        receipts: [SignalCommandStepReceipt],
        message: String
    ) {
        var receipts: [SignalCommandStepReceipt] = []
        var encounteredFailure = false

        for step in plan.steps {
            try Task.checkCancellation()
            let context = SignalCommandExecutionContext(
                runID: runID,
                planID: plan.id,
                stepID: step.id
            )
            do {
                let message = try await withTimeout(
                    milliseconds: step.timeoutMilliseconds
                ) {
                    try context.checkCancellation()
                    return try await performer.perform(step.action, context: context)
                }
                receipts.append(
                    SignalCommandStepReceipt(
                        stepID: step.id,
                        actionKind: step.action.kind,
                        status: .success,
                        message: message
                    )
                )
            } catch is CancellationError {
                receipts.append(
                    SignalCommandStepReceipt(
                        stepID: step.id,
                        actionKind: step.action.kind,
                        status: .cancelled,
                        message: "Cancelled."
                    )
                )
                throw CancellationError()
            } catch SignalCommandExecutionError.timedOut {
                encounteredFailure = true
                receipts.append(
                    SignalCommandStepReceipt(
                        stepID: step.id,
                        actionKind: step.action.kind,
                        status: .timedOut,
                        message: "Step timeout exceeded."
                    )
                )
                if step.failurePolicy == .stop {
                    return (.timedOut, receipts, "A command step timed out.")
                }
            } catch {
                encounteredFailure = true
                receipts.append(
                    SignalCommandStepReceipt(
                        stepID: step.id,
                        actionKind: step.action.kind,
                        status: .failure,
                        message: error.localizedDescription
                    )
                )
                if step.failurePolicy == .stop {
                    return (.failure, receipts, "A command step failed.")
                }
            }
        }

        return encounteredFailure
            ? (.failure, receipts, "Command finished with one or more failed steps.")
            : (.success, receipts, "Command completed.")
    }
}

private func withTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self, returning: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await ContinuousClock().sleep(
                for: .milliseconds(milliseconds)
            )
            throw SignalCommandExecutionError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else {
            throw SignalCommandExecutionError.timedOut
        }
        return first
    }
}
