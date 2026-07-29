import Foundation

public protocol SignalCustomCommandRepository: Sendable {
    func loadOrInstallDefaults() async throws -> SignalCommandDocument
    func save(_ document: SignalCommandDocument) async throws
    func importDocument(from source: URL) async throws
        -> SignalCommandDocument
    func export(
        _ document: SignalCommandDocument,
        to destination: URL
    ) async throws
}

extension SignalCommandRepository: SignalCustomCommandRepository {}

public enum SignalCustomCommandDraftAction: Equatable, Sendable {
    case openHTTPSURL(String)
    case boltPrompt(String)
    case spotifyNextTrack

    public var title: String {
        switch self {
        case .openHTTPSURL: "Open HTTPS URL"
        case .boltPrompt: "Submit reviewed Bolt prompt"
        case .spotifyNextTrack: "Next Spotify track"
        }
    }
}

public struct SignalCustomCommandStepDraft:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String
    public var action: SignalCustomCommandDraftAction
    public var timeoutMilliseconds: Int
    public var failurePolicy: SignalCommandFailurePolicy

    public init(
        id: String,
        action: SignalCustomCommandDraftAction,
        timeoutMilliseconds: Int = 10_000,
        failurePolicy: SignalCommandFailurePolicy = .stop
    ) {
        self.id = id
        self.action = action
        self.timeoutMilliseconds = timeoutMilliseconds
        self.failurePolicy = failurePolicy
    }
}

public struct SignalCustomCommandReview: Equatable, Sendable {
    public var name: String
    public var details: String
    public var orderedSteps: [SignalCustomCommandStepDraft]
    public var isUnconfigured: Bool

    public init(
        name: String,
        details: String,
        orderedSteps: [SignalCustomCommandStepDraft],
        isUnconfigured: Bool = false
    ) {
        self.name = name
        self.details = details
        self.orderedSteps = orderedSteps
        self.isUnconfigured = isUnconfigured
    }
}

public struct SignalCustomCommandValidationPreview:
    Equatable,
    Sendable
{
    public var isValid: Bool
    public var isUnconfigured: Bool
    public var summary: String
    public var orderedActionTitles: [String]
    public var messages: [String]

    /// Validation previews are intentionally incapable of execution.
    public let willExecute = false

    public init(
        isValid: Bool,
        isUnconfigured: Bool,
        summary: String,
        orderedActionTitles: [String],
        messages: [String]
    ) {
        self.isValid = isValid
        self.isUnconfigured = isUnconfigured
        self.summary = summary
        self.orderedActionTitles = orderedActionTitles
        self.messages = messages
    }
}

public enum SignalCustomCommandEditorPhase: Equatable, Sendable {
    case unloaded
    case editing
    case reviewing
    case saving
    case saved
    case failed(String)
}

public struct SignalCustomCommandPlanTestResult: Equatable, Sendable {
    public var succeeded: Bool
    public var message: String

    public init(succeeded: Bool, message: String) {
        self.succeeded = succeeded
        self.message = message
    }
}

public typealias SignalCustomCommandPlanTesting =
    @Sendable (SignalCommandPlan) async throws
        -> SignalCustomCommandPlanTestResult

public enum SignalCustomCommandTestState: Equatable, Sendable {
    case idle
    case testing
    case succeeded(String)
    case failed(String)
    case cancelled

    public var isTesting: Bool {
        if case .testing = self {
            return true
        }
        return false
    }
}

public enum SignalCustomCommandAuthoringError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case documentNotLoaded
    case fistCommandMissing
    case reviewRequired
    case draftChangedAfterReview
    case invalidName
    case invalidDetails
    case invalidStepCount
    case invalidStepIdentifier
    case invalidStepTimeout
    case unsafeText(field: String)
    case unsupportedDemoStep(String)
    case invalidMove
    case exportRequiresSavedDraft
    case unconfiguredCommandCannotBeTested
    case testAlreadyRunning
    case testRunnerUnavailable

    public var errorDescription: String? {
        switch self {
        case .documentNotLoaded:
            "Load the command document before editing."
        case .fistCommandMissing:
            "The configurable Fist command is missing."
        case .reviewRequired:
            "Review the complete command before saving."
        case .draftChangedAfterReview:
            "The draft changed after review. Review it again before saving."
        case .invalidName:
            "Name must contain safe text and be at most 80 characters."
        case .invalidDetails:
            "Description must contain safe text and be at most 500 characters."
        case .invalidStepCount:
            "A custom command requires one to fifty allowlisted steps."
        case .invalidStepIdentifier:
            "Every step must have a unique safe identifier."
        case .invalidStepTimeout:
            "Step timeouts must be between 100 and 60000 milliseconds."
        case .unsafeText(let field):
            "\(field) contains secret-like or prohibited automation text."
        case .unsupportedDemoStep(let reason):
            reason
        case .invalidMove:
            "The requested step move is outside the ordered step list."
        case .exportRequiresSavedDraft:
            "Save the reviewed Fist draft before exporting it."
        case .unconfiguredCommandCannotBeTested:
            "Add an allowlisted action and review Fist before testing it."
        case .testAlreadyRunning:
            "A Fist test is already running."
        case .testRunnerUnavailable:
            "Fist testing is unavailable in this context."
        }
    }
}

public struct SignalCustomCommandSafetyPolicy: Sendable {
    public init() {}

    public func validateAuthoringText(
        _ value: String,
        field: String,
        maximum: Int,
        permitsEmpty: Bool
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (permitsEmpty || !trimmed.isEmpty),
              value.count <= maximum,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            if field == "Name" {
                throw SignalCustomCommandAuthoringError.invalidName
            }
            if field == "Description" {
                throw SignalCustomCommandAuthoringError.invalidDetails
            }
            throw SignalCustomCommandAuthoringError.unsafeText(field: field)
        }
        guard !containsProhibitedAutomationIntent(trimmed),
              !looksSensitive(trimmed)
        else {
            throw SignalCustomCommandAuthoringError.unsafeText(field: field)
        }
        return trimmed
    }

    public func looksSensitive(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let sensitiveMarkers = [
            "password",
            "passcode",
            "api key",
            "api_key",
            "access token",
            "auth token",
            "private key",
            "client secret",
            "recovery code",
            "one-time code",
            "one time code",
            "-----begin private key-----",
        ]
        return sensitiveMarkers.contains(where: normalized.contains)
            || normalized.hasPrefix("sk-")
    }

    private func containsProhibitedAutomationIntent(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let prohibitedMarkers = [
            "rm -rf",
            "delete file",
            "delete folder",
            "remove file",
            "remove folder",
            "erase disk",
            "empty trash",
            "shell script",
            "run shell",
            "execute binary",
            "launch executable",
            "raw applescript",
            "run applescript",
            "osascript",
            "tell application",
            "sudo ",
            "administrator privilege",
            "root privilege",
            "chmod ",
            "chown ",
            "unlink ",
        ]
        return prohibitedMarkers.contains(where: normalized.contains)
    }
}

@MainActor
public final class SignalCustomCommandEditorModel: ObservableObject {
    @Published public private(set) var phase: SignalCustomCommandEditorPhase =
        .unloaded
    @Published public var name: String = ""
    @Published public var details: String = ""
    @Published public private(set) var steps: [SignalCustomCommandStepDraft] = []
    @Published public private(set) var review: SignalCustomCommandReview?
    @Published public private(set) var validationPreview:
        SignalCustomCommandValidationPreview?
    @Published public private(set) var operationMessage: String?
    @Published public private(set) var testState:
        SignalCustomCommandTestState = .idle

    private let repository: any SignalCustomCommandRepository
    private let validator: SignalCommandValidator
    private let urlPolicy: SignalCommandURLPolicy
    private let safetyPolicy: SignalCustomCommandSafetyPolicy
    private let naturalLanguageParser:
        SignalCustomCommandNaturalLanguageParser
    private let testReviewedPlan: SignalCustomCommandPlanTesting
    private let makeIdentifier: @MainActor () -> String

    private var document: SignalCommandDocument?
    private var draftRevision = 0
    private var persistedRevision = 0
    private var reviewedRevision: Int?
    private var isUnconfiguredDraft = false
    private var activeTestID: UUID?
    private var activeTestTask:
        Task<SignalCustomCommandPlanTestResult, Error>?

    public init(
        repository: any SignalCustomCommandRepository,
        validator: SignalCommandValidator = .init(),
        urlPolicy: SignalCommandURLPolicy = .init(),
        safetyPolicy: SignalCustomCommandSafetyPolicy = .init(),
        naturalLanguageParser:
            SignalCustomCommandNaturalLanguageParser = .init(),
        testReviewedPlan:
            @escaping SignalCustomCommandPlanTesting = { _ in
                throw SignalCustomCommandAuthoringError.testRunnerUnavailable
            },
        makeIdentifier: @escaping @MainActor () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.repository = repository
        self.validator = validator
        self.urlPolicy = urlPolicy
        self.safetyPolicy = safetyPolicy
        self.naturalLanguageParser = naturalLanguageParser
        self.testReviewedPlan = testReviewedPlan
        self.makeIdentifier = makeIdentifier
    }

    public var canSaveReviewedDraft: Bool {
        phase == .reviewing
            && reviewedRevision == draftRevision
            && review != nil
            && !testState.isTesting
    }

    public var canTestReviewedDraft: Bool {
        phase == .reviewing
            && reviewedRevision == draftRevision
            && review?.isUnconfigured == false
            && !testState.isTesting
    }

    public var hasUnsavedChanges: Bool {
        document != nil && draftRevision != persistedRevision
    }

    public func load() async throws {
        do {
            let loaded = try await repository.loadOrInstallDefaults()
            try load(document: loaded)
            operationMessage = "Loaded the local Fist command."
        } catch {
            phase = .failed(error.localizedDescription)
            operationMessage = error.localizedDescription
            throw error
        }
    }

    /// Imports only the validated configurable Fist definition. The seven
    /// fixed local commands always remain sourced from the loaded document,
    /// and the imported Fist still requires review and save.
    public func importFist(from source: URL) async throws {
        guard document != nil else {
            throw SignalCustomCommandAuthoringError.documentNotLoaded
        }
        do {
            let imported = try await repository.importDocument(from: source)
            try validator.validate(imported)
            guard let fist = imported.profile[.fist],
                  fist.isConfigurable else {
                throw SignalCustomCommandAuthoringError.fistCommandMissing
            }
            name = fist.name
            details = fist.details
            steps = fist.plan?.steps.map(makeDraftStep) ?? []
            isUnconfiguredDraft = fist.plan == nil
            invalidateReview(preservingUnconfiguredState: true)
            operationMessage =
                "Imported Fist draft. Review and save are still required."
        } catch {
            operationMessage = error.localizedDescription
            throw error
        }
    }

    /// Exports the last locally saved document. An unreviewed or unsaved
    /// draft is never silently exported as if it were active.
    public func exportSavedDocument(to destination: URL) async throws {
        guard let document else {
            throw SignalCustomCommandAuthoringError.documentNotLoaded
        }
        guard !hasUnsavedChanges else {
            throw SignalCustomCommandAuthoringError.exportRequiresSavedDraft
        }
        do {
            try await repository.export(document, to: destination)
            operationMessage = "Exported the saved command document."
        } catch {
            operationMessage = error.localizedDescription
            throw error
        }
    }

    public func resetFistToDefault() {
        guard let defaultFist =
            SignalDefaultCommandCatalog.document.profile[.fist] else {
            return
        }
        name = defaultFist.name
        details = defaultFist.details
        steps = []
        isUnconfiguredDraft = true
        invalidateReview(preservingUnconfiguredState: true)
        operationMessage =
            "Fist reset to the unconfigured default. Review before saving."
    }

    @discardableResult
    public func applyNaturalLanguageDraft(
        _ input: String
    ) throws -> SignalCustomCommandNaturalLanguageDraft {
        guard document != nil else {
            throw SignalCustomCommandAuthoringError.documentNotLoaded
        }
        do {
            let draft = try naturalLanguageParser.parse(input)
            name = draft.name
            details = draft.details
            steps = draft.orderedSteps
            isUnconfiguredDraft = false
            invalidateReview()
            operationMessage =
                "Created a deterministic draft. Validate and review before saving."
            return draft
        } catch {
            operationMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func previewValidation()
        -> SignalCustomCommandValidationPreview
    {
        do {
            let candidate = try makeReview()
            let preview = SignalCustomCommandValidationPreview(
                isValid: true,
                isUnconfigured: candidate.isUnconfigured,
                summary: candidate.isUnconfigured
                    ? "Fist will be saved as the unconfigured default."
                    : "Fist has \(candidate.orderedSteps.count) valid allowlisted step(s).",
                orderedActionTitles:
                    candidate.orderedSteps.map { $0.action.title },
                messages: [
                    "The seven fixed commands are unchanged.",
                    "This preview does not execute any action.",
                    "A separate review is still required before save.",
                ]
            )
            validationPreview = preview
            operationMessage = "Validation preview completed without execution."
            return preview
        } catch {
            let preview = SignalCustomCommandValidationPreview(
                isValid: false,
                isUnconfigured: false,
                summary: "Draft validation failed.",
                orderedActionTitles: steps.map { $0.action.title },
                messages: [
                    error.localizedDescription,
                    "No action was executed.",
                ]
            )
            validationPreview = preview
            operationMessage = error.localizedDescription
            return preview
        }
    }

    public func setName(_ value: String) {
        guard name != value else { return }
        name = value
        invalidateReview()
    }

    public func setDetails(_ value: String) {
        guard details != value else { return }
        details = value
        invalidateReview()
    }

    public func addStep(
        action: SignalCustomCommandDraftAction,
        timeoutMilliseconds: Int = 10_000,
        failurePolicy: SignalCommandFailurePolicy = .stop
    ) {
        let step = SignalCustomCommandStepDraft(
            id: "signal.custom.fist.step-\(makeIdentifier())",
            action: action,
            timeoutMilliseconds: timeoutMilliseconds,
            failurePolicy: failurePolicy
        )
        steps.append(step)
        invalidateReview()
    }

    public func updateStep(_ step: SignalCustomCommandStepDraft) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }),
              steps[index] != step else {
            return
        }
        steps[index] = step
        invalidateReview()
    }

    public func deleteStep(id: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else {
            return
        }
        steps.remove(at: index)
        invalidateReview()
    }

    public func moveStep(id: String, to destinationIndex: Int) throws {
        guard let sourceIndex = steps.firstIndex(where: { $0.id == id }),
              steps.indices.contains(destinationIndex) else {
            throw SignalCustomCommandAuthoringError.invalidMove
        }
        guard sourceIndex != destinationIndex else { return }
        let step = steps.remove(at: sourceIndex)
        steps.insert(step, at: destinationIndex)
        invalidateReview()
    }

    public func replaceSteps(
        with reviewedDemoSteps: [SignalCustomCommandStepDraft]
    ) {
        steps = reviewedDemoSteps
        invalidateReview()
    }

    @discardableResult
    public func beginReview() throws -> SignalCustomCommandReview {
        guard document != nil else {
            throw SignalCustomCommandAuthoringError.documentNotLoaded
        }
        let candidate = try makeReview()
        review = candidate
        reviewedRevision = draftRevision
        phase = .reviewing
        return candidate
    }

    public func resumeEditing() {
        guard document != nil else { return }
        cancelActiveTest(nextState: .idle)
        review = nil
        reviewedRevision = nil
        phase = .editing
    }

    /// Executes only the currently reviewed, closed-schema draft. Testing is
    /// explicit, never persists the draft, and defaults to a fail-closed
    /// runner until production injects the native command executor.
    @discardableResult
    public func testReviewed() async throws
        -> SignalCustomCommandPlanTestResult
    {
        guard !testState.isTesting else {
            throw SignalCustomCommandAuthoringError.testAlreadyRunning
        }

        let plan: SignalCommandPlan
        do {
            guard phase == .reviewing,
                  let review,
                  reviewedRevision != nil else {
                throw SignalCustomCommandAuthoringError.reviewRequired
            }
            guard reviewedRevision == draftRevision else {
                throw SignalCustomCommandAuthoringError
                    .draftChangedAfterReview
            }
            plan = try makeRuntimePlan(from: review)
        } catch {
            let message = error.localizedDescription
            testState = .failed(message)
            operationMessage = message
            throw error
        }

        let testID = UUID()
        let testReviewedPlan = self.testReviewedPlan
        let task = Task {
            try await testReviewedPlan(plan)
        }
        activeTestID = testID
        activeTestTask = task
        testState = .testing
        operationMessage = "Testing the reviewed Fist command…"

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard activeTestID == testID else {
                throw CancellationError()
            }
            activeTestID = nil
            activeTestTask = nil
            let message = result.message.isEmpty
                ? (result.succeeded
                    ? "Reviewed Fist test completed."
                    : "Reviewed Fist test failed.")
                : result.message
            testState = result.succeeded
                ? .succeeded(message)
                : .failed(message)
            operationMessage = message
            return SignalCustomCommandPlanTestResult(
                succeeded: result.succeeded,
                message: message
            )
        } catch is CancellationError {
            if activeTestID == testID {
                activeTestID = nil
                activeTestTask = nil
                testState = .cancelled
                operationMessage = "Fist test cancelled."
            }
            throw CancellationError()
        } catch {
            if activeTestID == testID {
                activeTestID = nil
                activeTestTask = nil
                let message = error.localizedDescription
                testState = .failed(message)
                operationMessage = message
            }
            throw error
        }
    }

    public func cancelTest() {
        guard testState.isTesting else { return }
        cancelActiveTest(nextState: .cancelled)
        operationMessage = "Fist test cancelled."
    }

    public func saveReviewed() async throws {
        guard let document else {
            throw SignalCustomCommandAuthoringError.documentNotLoaded
        }
        guard let review, reviewedRevision != nil else {
            throw SignalCustomCommandAuthoringError.reviewRequired
        }
        guard reviewedRevision == draftRevision else {
            throw SignalCustomCommandAuthoringError.draftChangedAfterReview
        }

        let plan: SignalCommandPlan?
        if review.isUnconfigured {
            plan = nil
        } else {
            plan = try makeRuntimePlan(from: review)
        }

        guard let fistIndex = document.profile.commands.firstIndex(
            where: { $0.gesture == .fist && $0.isConfigurable }
        ) else {
            throw SignalCustomCommandAuthoringError.fistCommandMissing
        }

        var candidate = document
        let originalFist = candidate.profile.commands[fistIndex]
        candidate.profile.commands[fistIndex] = SignalCommandDefinition(
            id: originalFist.id,
            gesture: .fist,
            name: review.name,
            details: review.details,
            isConfigurable: true,
            plan: plan
        )
        try validator.validate(candidate)

        phase = .saving
        do {
            try await repository.save(candidate)
            self.document = candidate
            persistedRevision = draftRevision
            phase = .saved
            operationMessage = review.isUnconfigured
                ? "Saved Fist as the unconfigured default."
                : "Saved the reviewed Fist command locally."
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    private func load(document: SignalCommandDocument) throws {
        cancelActiveTest(nextState: .idle)
        try validator.validate(document)
        guard let fist = document.profile[.fist], fist.isConfigurable else {
            throw SignalCustomCommandAuthoringError.fistCommandMissing
        }
        self.document = document
        name = fist.name
        details = fist.details
        steps = fist.plan?.steps.map(makeDraftStep) ?? []
        isUnconfiguredDraft = fist.plan == nil
        draftRevision = 0
        persistedRevision = 0
        reviewedRevision = nil
        review = nil
        validationPreview = nil
        testState = .idle
        operationMessage = nil
        phase = .editing
    }

    private func invalidateReview(
        preservingUnconfiguredState: Bool = false
    ) {
        cancelActiveTest(nextState: .idle)
        if !preservingUnconfiguredState {
            isUnconfiguredDraft = false
        }
        draftRevision += 1
        reviewedRevision = nil
        review = nil
        validationPreview = nil
        if document != nil {
            phase = .editing
        }
    }

    private func cancelActiveTest(
        nextState: SignalCustomCommandTestState
    ) {
        activeTestTask?.cancel()
        activeTestTask = nil
        activeTestID = nil
        testState = nextState
    }

    private func makeRuntimePlan(
        from review: SignalCustomCommandReview
    ) throws -> SignalCommandPlan {
        guard !review.isUnconfigured else {
            throw SignalCustomCommandAuthoringError
                .unconfiguredCommandCannotBeTested
        }
        let runtimeSteps = try review.orderedSteps.map(makeRuntimeStep)
        let totalTimeout = runtimeSteps.reduce(5_000) {
            min(300_000, $0 + $1.timeoutMilliseconds)
        }
        return SignalCommandPlan(
            id: "signal.custom.fist.plan",
            steps: runtimeSteps,
            timeoutMilliseconds: max(100, totalTimeout)
        )
    }

    private func makeReview() throws -> SignalCustomCommandReview {
        let reviewedName = try safetyPolicy.validateAuthoringText(
            name,
            field: "Name",
            maximum: 80,
            permitsEmpty: false
        )
        let reviewedDetails = try safetyPolicy.validateAuthoringText(
            details,
            field: "Description",
            maximum: 500,
            permitsEmpty: true
        )
        let defaultFist =
            SignalDefaultCommandCatalog.document.profile[.fist]
        let isReviewedUnconfigured =
            isUnconfiguredDraft
            && steps.isEmpty
            && reviewedName == defaultFist?.name
            && reviewedDetails == defaultFist?.details
        guard isReviewedUnconfigured || (1...50).contains(steps.count) else {
            throw SignalCustomCommandAuthoringError.invalidStepCount
        }

        var identifiers: Set<String> = []
        for step in steps {
            guard Self.isSafeIdentifier(step.id),
                  identifiers.insert(step.id).inserted else {
                throw SignalCustomCommandAuthoringError.invalidStepIdentifier
            }
            guard (100...60_000).contains(step.timeoutMilliseconds) else {
                throw SignalCustomCommandAuthoringError.invalidStepTimeout
            }
            _ = try makeRuntimeStep(step)
        }
        return SignalCustomCommandReview(
            name: reviewedName,
            details: reviewedDetails,
            orderedSteps: steps,
            isUnconfigured: isReviewedUnconfigured
        )
    }

    private func makeRuntimeStep(
        _ draft: SignalCustomCommandStepDraft
    ) throws -> SignalCommandStep {
        let runtimeAction: SignalCommandAction
        switch draft.action {
        case .openHTTPSURL(let rawURL):
            let url = try urlPolicy.validate(rawURL)
            runtimeAction = .openURL(.init(url: url.absoluteString))
        case .boltPrompt(let prompt):
            let reviewedPrompt = try safetyPolicy.validateAuthoringText(
                prompt,
                field: "Bolt prompt",
                maximum: 512,
                permitsEmpty: false
            )
            runtimeAction = .boltPrompt(.init(prompt: reviewedPrompt))
        case .spotifyNextTrack:
            runtimeAction = .spotifyNextTrack(.init())
        }
        return SignalCommandStep(
            id: draft.id,
            action: runtimeAction,
            timeoutMilliseconds: draft.timeoutMilliseconds,
            failurePolicy: draft.failurePolicy
        )
    }

    private func makeDraftStep(
        _ step: SignalCommandStep
    ) -> SignalCustomCommandStepDraft {
        let action: SignalCustomCommandDraftAction
        switch step.action {
        case .openURL(let payload):
            action = .openHTTPSURL(payload.url)
        case .boltPrompt(let payload):
            action = .boltPrompt(payload.prompt)
        case .spotifyNextTrack:
            action = .spotifyNextTrack
        }
        return SignalCustomCommandStepDraft(
            id: step.id,
            action: action,
            timeoutMilliseconds: step.timeoutMilliseconds,
            failurePolicy: step.failurePolicy
        )
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn:
                        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
                ).contains($0)
            }
    }
}
