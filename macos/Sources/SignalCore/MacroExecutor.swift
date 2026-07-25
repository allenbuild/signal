import Foundation

public enum ReceiptStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case skipped
}

public struct ActionReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var stepID: String
    public var action: ActionKind
    public var status: ReceiptStatus
    public var message: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        stepID: String,
        action: ActionKind,
        status: ReceiptStatus,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stepID = stepID
        self.action = action
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }
}

public struct MacroRunReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var planID: String
    public var status: ReceiptStatus
    public var stepReceipts: [ActionReceipt]
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        id: UUID = UUID(),
        planID: String,
        status: ReceiptStatus,
        stepReceipts: [ActionReceipt],
        startedAt: Date,
        finishedAt: Date
    ) {
        self.id = id
        self.planID = planID
        self.status = status
        self.stepReceipts = stepReceipts
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public protocol ActionPerforming: Sendable {
    func perform(_ step: ActionStep) async throws -> String
}

public protocol ConfirmationProviding: Sendable {
    func approve(plan: ActionPlan, step: ActionStep?) async -> Bool
}

public struct AllowAllConfirmations: ConfirmationProviding {
    public init() {}
    public func approve(plan: ActionPlan, step: ActionStep?) async -> Bool { true }
}

public struct DenyAllConfirmations: ConfirmationProviding {
    public init() {}
    public func approve(plan: ActionPlan, step: ActionStep?) async -> Bool { false }
}

public enum MacroExecutionError: Error, LocalizedError {
    case timedOut
    case confirmationDenied
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "The action timed out."
        case .confirmationDenied: return "Confirmation was denied."
        case .alreadyRunning: return "Another macro is already running."
        }
    }
}

public enum SafetyAuthorizationError: Error, LocalizedError {
    case outputPaused

    public var errorDescription: String? {
        "Output is paused; the effect was blocked."
    }
}

public struct SafetyGatedPerformer: ActionPerforming {
    private let gate: SafetyGate
    private let underlying: any ActionPerforming

    public init(gate: SafetyGate, underlying: any ActionPerforming) {
        self.gate = gate
        self.underlying = underlying
    }

    public func perform(_ step: ActionStep) async throws -> String {
        guard !gate.isPaused else { throw SafetyAuthorizationError.outputPaused }
        try Task.checkCancellation()
        let result = try await underlying.perform(step)
        guard !gate.isPaused else { throw SafetyAuthorizationError.outputPaused }
        try Task.checkCancellation()
        return result
    }
}

/// Validates before execution, supports timeout/cancellation, and produces typed receipts.
public actor MacroExecutor {
    private var activeTask: Task<MacroRunReceipt, Never>?

    public init() {}

    public var isRunning: Bool { activeTask != nil }

    public func execute(
        _ plan: ActionPlan,
        performer: any ActionPerforming,
        confirmations: any ConfirmationProviding = DenyAllConfirmations()
    ) async -> MacroRunReceipt {
        guard activeTask == nil else {
            return MacroRunReceipt(
                planID: plan.id,
                status: .failure,
                stepReceipts: [],
                startedAt: Date(),
                finishedAt: Date()
            )
        }

        let task = Task {
            await Self.run(plan, performer: performer, confirmations: confirmations)
        }
        activeTask = task
        let result = await task.value
        activeTask = nil
        return result
    }

    public func cancel() {
        activeTask?.cancel()
    }

    private static func run(
        _ plan: ActionPlan,
        performer: any ActionPerforming,
        confirmations: any ConfirmationProviding
    ) async -> MacroRunReceipt {
        let started = Date()
        do {
            try ActionPlanValidator().validate(plan)
        } catch {
            return MacroRunReceipt(
                planID: plan.id,
                status: .failure,
                stepReceipts: [],
                startedAt: started,
                finishedAt: Date()
            )
        }

        let planApproved = plan.confirmationRequired
            ? await confirmations.approve(plan: plan, step: nil)
            : true
        if !planApproved {
            return MacroRunReceipt(
                planID: plan.id,
                status: .cancelled,
                stepReceipts: [],
                startedAt: started,
                finishedAt: Date()
            )
        }

        var receipts: [ActionReceipt] = []
        var finalStatus: ReceiptStatus = .success

        for step in plan.steps {
            if Task.isCancelled {
                finalStatus = .cancelled
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .cancelled,
                    message: "Cancelled by emergency pause or user."
                ))
                break
            }
            if Date().timeIntervalSince(started) > plan.timeoutSeconds {
                finalStatus = .failure
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .failure,
                    message: "Whole-plan timeout exceeded."
                ))
                break
            }
            let stepApproved = step.confirmationRequired
                ? await confirmations.approve(plan: plan, step: step)
                : true
            if !stepApproved {
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .skipped,
                    message: "Step confirmation denied."
                ))
                if step.onFailure == .stop {
                    finalStatus = .cancelled
                    break
                }
                continue
            }

            do {
                let message = try await withTimeout(seconds: step.timeoutSeconds) {
                    try await performer.perform(step)
                }
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .success,
                    message: message
                ))
            } catch is CancellationError {
                finalStatus = .cancelled
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .cancelled,
                    message: "Cancelled."
                ))
                break
            } catch {
                receipts.append(ActionReceipt(
                    stepID: step.id,
                    action: step.action,
                    status: .failure,
                    message: error.localizedDescription
                ))
                if step.onFailure == .stop || step.onFailure == .ask {
                    finalStatus = .failure
                    break
                }
            }
        }

        if finalStatus == .success, receipts.contains(where: { $0.status == .failure }) {
            finalStatus = .failure
        }
        return MacroRunReceipt(
            planID: plan.id,
            status: finalStatus,
            stepReceipts: receipts,
            startedAt: started,
            finishedAt: Date()
        )
    }
}

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.001) * 1_000_000_000))
            throw MacroExecutionError.timedOut
        }
        guard let value = try await group.next() else {
            throw MacroExecutionError.timedOut
        }
        group.cancelAll()
        return value
    }
}
