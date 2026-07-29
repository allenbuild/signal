import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalCustomCommandAuthoringTests: XCTestCase {
    func testEditorLoadsOnlyFistAndSupportsOrderedEditDeleteAndMove() async throws {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let identifiers = IdentifierSequence()
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { identifiers.next() }
        )

        try await model.load()
        XCTAssertEqual(model.name, "Custom Command")
        XCTAssertTrue(model.steps.isEmpty)

        model.setName("My Fist command")
        model.setDetails("Two reviewed runtime steps.")
        model.addStep(action: .openHTTPSURL("https://example.com/first"))
        model.addStep(action: .spotifyNextTrack)

        let firstID = try XCTUnwrap(model.steps.first?.id)
        try model.moveStep(id: firstID, to: 1)
        XCTAssertEqual(model.steps.first?.action, .spotifyNextTrack)

        model.deleteStep(id: firstID)
        XCTAssertEqual(model.steps.map(\.action), [.spotifyNextTrack])
        XCTAssertEqual(model.phase, .editing)
        XCTAssertNil(model.review)
    }

    func testReviewedSavePersistsFistAndPreservesFixedCatalog() async throws {
        let original = SignalDefaultCommandCatalog.document
        let repository = InMemoryCustomCommandRepository(document: original)
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "reviewed-step" }
        )

        try await model.load()
        model.setName("Reviewed Fist")
        model.setDetails("Open one reviewed public destination.")
        model.addStep(action: .openHTTPSURL("https://example.com/path"))
        _ = try model.beginReview()
        try await model.saveReviewed()

        let savedDocument = await repository.savedDocument()
        let saved = try XCTUnwrap(savedDocument)
        XCTAssertEqual(saved.profile.commands.count, 8)
        XCTAssertEqual(saved.profile[.fist]?.name, "Reviewed Fist")
        XCTAssertEqual(
            saved.profile[.fist]?.plan?.steps.first?.action,
            .openURL(.init(url: "https://example.com/path"))
        )
        for gesture in SignalCommandGesture.allCases where gesture != .fist {
            XCTAssertEqual(saved.profile[gesture], original.profile[gesture])
        }
    }

    func testDraftMustBeReviewedAgainAfterAnyEdit() async throws {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)

        await XCTAssertThrowsErrorAsync {
            try await model.saveReviewed()
        }

        _ = try model.beginReview()
        model.setDetails("Changed after review")
        XCTAssertFalse(model.canSaveReviewedDraft)
        await XCTAssertThrowsErrorAsync {
            try await model.saveReviewed()
        }
        let saveCount = await repository.saveCount()
        XCTAssertEqual(saveCount, 0)
    }

    func testUnsafeAutomationTextCannotPassReview() async throws {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "step" }
        )
        try await model.load()
        model.setName("Unsafe")
        model.setDetails("Run shell script with sudo access")
        model.addStep(action: .spotifyNextTrack)

        XCTAssertThrowsError(try model.beginReview()) { error in
            XCTAssertEqual(
                error as? SignalCustomCommandAuthoringError,
                .unsafeText(field: "Description")
            )
        }
        let saveCount = await repository.saveCount()
        XCTAssertEqual(saveCount, 0)
    }

    func testTeachByDemoRedactsSecureTextWithoutRetainingAProposal() throws {
        let identifiers = IdentifierSequence()
        let model = SignalTeachByDemoModel(
            makeIdentifier: { identifiers.next() }
        )
        let secureTarget = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: "com.example.Login",
            role: "AXSecureTextField",
            title: "Password",
            identifier: "password-field",
            isSecureField: true,
            wasUserReviewed: true
        )

        model.beginCapture()
        XCTAssertThrowsError(
            try model.recordTypedText(
                "super-secret-value",
                target: secureTarget,
                isSecret: true
            )
        ) { error in
            XCTAssertEqual(
                error as? SignalTeachByDemoError,
                .secureValueRedacted
            )
        }
        XCTAssertTrue(model.proposals.isEmpty)
        XCTAssertEqual(model.redactedEventCount, 1)
        XCTAssertFalse(model.notice.contains("super-secret-value"))
    }

    func testUnsupportedDemoProposalsAreVisibleButCannotConvertOrSave() throws {
        let identifiers = IdentifierSequence()
        let model = SignalTeachByDemoModel(
            makeIdentifier: { identifiers.next() }
        )
        let target = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: "com.example.Browser",
            role: "AXButton",
            title: "Continue",
            identifier: "continue",
            wasUserReviewed: true
        )

        model.beginCapture()
        try model.recordAccessibilityClick(target: target)
        try model.recordTypedText(
            "Reviewed text",
            target: target,
            isSecret: false
        )
        try model.recordKeyCombo(
            .init(key: "K", modifiers: [.command, .shift])
        )
        try model.recordWait(milliseconds: 500)
        try model.finishCaptureForReview()

        for proposal in model.proposals {
            try model.setReviewed(true, proposalID: proposal.id)
        }
        XCTAssertEqual(model.proposals.count, 4)
        XCTAssertTrue(
            model.proposals.allSatisfy {
                if case .unsupported = $0.runtimeSupport { true } else { false }
            }
        )
        XCTAssertFalse(model.canApplyToRuntime)
        XCTAssertThrowsError(try model.reviewedRuntimeSteps()) { error in
            guard case .unsupportedProposal =
                error as? SignalTeachByDemoError else {
                return XCTFail("Expected unsupported proposal, got \(error)")
            }
        }
    }

    func testReviewedHTTPSDemoCanBecomeASavableFistStep() async throws {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let identifiers = IdentifierSequence()
        let editor = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { identifiers.next() }
        )
        let demo = SignalTeachByDemoModel(
            makeIdentifier: { identifiers.next() }
        )

        try await editor.load()
        editor.setName("Demo URL")
        editor.setDetails("One reviewed HTTPS proposal.")

        demo.beginCapture()
        try demo.recordOpenHTTPSURL("https://example.com/demo")
        try demo.finishCaptureForReview()
        let proposalID = try XCTUnwrap(demo.proposals.first?.id)
        try demo.setReviewed(true, proposalID: proposalID)
        XCTAssertTrue(demo.canApplyToRuntime)

        editor.replaceSteps(with: try demo.reviewedRuntimeSteps())
        _ = try editor.beginReview()
        try await editor.saveReviewed()

        let savedDocument = await repository.savedDocument()
        let saved = try XCTUnwrap(savedDocument)
        XCTAssertEqual(
            saved.profile[.fist]?.plan?.steps.first?.action,
            .openURL(.init(url: "https://example.com/demo"))
        )
    }

    func testDemoRejectsNonHTTPSAndUnreviewedTargets() {
        let model = SignalTeachByDemoModel()
        let target = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: "com.example.App",
            role: "AXButton",
            title: "Go",
            wasUserReviewed: false
        )
        model.beginCapture()

        XCTAssertThrowsError(
            try model.recordOpenHTTPSURL("http://example.com")
        )
        XCTAssertThrowsError(
            try model.recordAccessibilityClick(target: target)
        ) { error in
            XCTAssertEqual(
                error as? SignalTeachByDemoError,
                .targetNotReviewed
            )
        }
        XCTAssertTrue(model.proposals.isEmpty)
    }

    func testImportAdoptsOnlyFistAndStillRequiresReviewedSave()
        async throws
    {
        let local = SignalDefaultCommandCatalog.document
        var imported = local
        let fistIndex = try XCTUnwrap(
            imported.profile.commands.firstIndex {
                $0.gesture == .fist
            }
        )
        imported.profile.commands[fistIndex] = SignalCommandDefinition(
            id: imported.profile.commands[fistIndex].id,
            gesture: .fist,
            name: "Imported Fist",
            details: "A reviewed imported draft.",
            isConfigurable: true,
            plan: SignalCommandPlan(
                id: "signal.custom.import.plan",
                steps: [
                    SignalCommandStep(
                        id: "signal.custom.import.step-1",
                        action: .spotifyNextTrack(.init()),
                        timeoutMilliseconds: 15_000
                    )
                ],
                timeoutMilliseconds: 20_000
            )
        )
        let repository = InMemoryCustomCommandRepository(
            document: local,
            importedDocument: imported
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository
        )

        try await model.load()
        try await model.importFist(
            from: URL(fileURLWithPath: "/tmp/import.json")
        )
        XCTAssertEqual(model.name, "Imported Fist")
        XCTAssertEqual(model.steps.map(\.action), [.spotifyNextTrack])
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNil(model.review)
        await XCTAssertThrowsErrorAsync {
            try await model.saveReviewed()
        }

        _ = try model.beginReview()
        try await model.saveReviewed()
        let savedDocument = await repository.savedDocument()
        let saved = try XCTUnwrap(savedDocument)
        for gesture in SignalCommandGesture.allCases
            where gesture != .fist {
            XCTAssertEqual(saved.profile[gesture], local.profile[gesture])
        }
    }

    func testExportRefusesUnsavedDraftThenExportsReviewedSave()
        async throws
    {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "export-step" }
        )
        let destination = URL(fileURLWithPath: "/tmp/export.json")
        try await model.load()
        model.addStep(action: .spotifyNextTrack)

        await XCTAssertThrowsErrorAsync {
            try await model.exportSavedDocument(to: destination)
        }
        let exportCountBeforeSave = await repository.exportCount()
        XCTAssertEqual(exportCountBeforeSave, 0)

        _ = try model.beginReview()
        try await model.saveReviewed()
        try await model.exportSavedDocument(to: destination)
        let exportCountAfterSave = await repository.exportCount()
        let exported = await repository.exportedDocument()
        let savedAfterExport = await repository.savedDocument()
        XCTAssertEqual(exportCountAfterSave, 1)
        XCTAssertEqual(exported, savedAfterExport)
    }

    func testResetSavesUnconfiguredFistAndPreservesFixedCatalog()
        async throws
    {
        let original = SignalDefaultCommandCatalog.document
        let repository = InMemoryCustomCommandRepository(
            document: original
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "reset-step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)

        model.resetFistToDefault()
        let review = try model.beginReview()
        XCTAssertTrue(review.isUnconfigured)
        XCTAssertTrue(review.orderedSteps.isEmpty)
        try await model.saveReviewed()

        let savedDocument = await repository.savedDocument()
        let saved = try XCTUnwrap(savedDocument)
        XCTAssertNil(saved.profile[.fist]?.plan)
        XCTAssertEqual(
            saved.profile[.fist],
            original.profile[.fist]
        )
        for gesture in SignalCommandGesture.allCases
            where gesture != .fist {
            XCTAssertEqual(saved.profile[gesture], original.profile[gesture])
        }
    }

    func testNaturalLanguageParserIsDeterministicAndClosed() throws {
        let parser = SignalCustomCommandNaturalLanguageParser()
        let input = """
        name: Morning setup
        description: Open one reviewed page, then continue music.
        open: https://example.com/path
        bolt: Build a reviewed public landing page
        spotify: next
        """

        let first = try parser.parse(input)
        let second = try parser.parse(input)
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.orderedSteps.map(\.id),
            [
                "signal.custom.fist.nl.step-1",
                "signal.custom.fist.nl.step-2",
                "signal.custom.fist.nl.step-3",
            ]
        )
        XCTAssertEqual(
            first.orderedSteps.map(\.action),
            [
                .openHTTPSURL("https://example.com/path"),
                .boltPrompt("Build a reviewed public landing page"),
                .spotifyNextTrack,
            ]
        )

        for unsafe in [
            "name: Bad\ndescription: run shell script\nspotify: next",
            "name: Bad\ndescription: Safe\nopen: http://example.com",
            "name: Bad\ndescription: Safe\napplescript: tell application",
            "name: Bad\ndescription: delete file\nspotify: next",
        ] {
            XCTAssertThrowsError(try parser.parse(unsafe))
        }
    }

    func testValidationPreviewNeverExecutesOrSaves() async throws {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            makeIdentifier: { "preview-step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)

        let preview = model.previewValidation()
        XCTAssertTrue(preview.isValid)
        XCTAssertFalse(preview.willExecute)
        XCTAssertEqual(
            preview.orderedActionTitles,
            ["Next Spotify track"]
        )
        let saveCountAfterValidPreview = await repository.saveCount()
        XCTAssertEqual(saveCountAfterValidPreview, 0)

        model.setDetails("run shell script")
        let invalid = model.previewValidation()
        XCTAssertFalse(invalid.isValid)
        XCTAssertFalse(invalid.willExecute)
        let saveCountAfterInvalidPreview = await repository.saveCount()
        XCTAssertEqual(saveCountAfterInvalidPreview, 0)
    }

    func testExplicitTestRequiresCurrentReviewBeforeAnySideEffect()
        async throws
    {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let effects = CustomCommandPlanTestEffects(
            outcome: .success("Test completed.", delayMilliseconds: 0)
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            testReviewedPlan: { plan in
                try await effects.run(plan)
            },
            makeIdentifier: { "review-required-step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)

        do {
            _ = try await model.testReviewed()
            XCTFail("An unreviewed draft must not be tested.")
        } catch {
            XCTAssertEqual(
                error as? SignalCustomCommandAuthoringError,
                .reviewRequired
            )
        }

        let callCount = await effects.callCount()
        let saveCount = await repository.saveCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(
            model.testState,
            .failed(
                SignalCustomCommandAuthoringError.reviewRequired
                    .localizedDescription
            )
        )
    }

    func testExplicitTestExecutesReviewedClosedPlanExactlyOnceAndNeverSaves()
        async throws
    {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let effects = CustomCommandPlanTestEffects(
            outcome: .success(
                "Reviewed action completed.",
                delayMilliseconds: 75
            )
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            testReviewedPlan: { plan in
                try await effects.run(plan)
            },
            makeIdentifier: { "exactly-once-step" }
        )
        try await model.load()
        model.setName("Testable Fist")
        model.addStep(
            action: .openHTTPSURL("https://example.com/reviewed")
        )
        _ = try model.beginReview()

        let firstClick = Task {
            try await model.testReviewed()
        }
        await waitForTestCalls(1, effects: effects)

        do {
            _ = try await model.testReviewed()
            XCTFail("A concurrent duplicate test must be rejected.")
        } catch {
            XCTAssertEqual(
                error as? SignalCustomCommandAuthoringError,
                .testAlreadyRunning
            )
        }

        let result = try await firstClick.value
        let plans = await effects.receivedPlans()
        let saveCount = await repository.saveCount()
        XCTAssertEqual(result.message, "Reviewed action completed.")
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(
            plans.first?.steps.map(\.action),
            [
                .openURL(
                    .init(url: "https://example.com/reviewed")
                )
            ]
        )
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(
            model.testState,
            .succeeded("Reviewed action completed.")
        )
    }

    func testExplicitTestReportsInjectedFailureTruthfullyWithoutSaving()
        async throws
    {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let effects = CustomCommandPlanTestEffects(
            outcome: .failure("Camera permission was denied.")
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            testReviewedPlan: { plan in
                try await effects.run(plan)
            },
            makeIdentifier: { "failure-step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)
        _ = try model.beginReview()

        do {
            _ = try await model.testReviewed()
            XCTFail("The injected failure must be returned.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Camera permission was denied."
            )
        }

        let callCount = await effects.callCount()
        let saveCount = await repository.saveCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(
            model.testState,
            .failed("Camera permission was denied.")
        )
    }

    func testExplicitTestCancellationCancelsInjectedWorkAndNeverSaves()
        async throws
    {
        let repository = InMemoryCustomCommandRepository(
            document: SignalDefaultCommandCatalog.document
        )
        let effects = CustomCommandPlanTestEffects(
            outcome: .success(
                "Must not complete.",
                delayMilliseconds: 10_000
            )
        )
        let model = SignalCustomCommandEditorModel(
            repository: repository,
            testReviewedPlan: { plan in
                try await effects.run(plan)
            },
            makeIdentifier: { "cancel-step" }
        )
        try await model.load()
        model.addStep(action: .spotifyNextTrack)
        _ = try model.beginReview()

        let testTask = Task {
            try await model.testReviewed()
        }
        await waitForTestCalls(1, effects: effects)
        model.cancelTest()

        do {
            _ = try await testTask.value
            XCTFail("Cancellation must propagate to the test task.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }

        let saveCount = await repository.saveCount()
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(model.testState, .cancelled)
    }
}

private actor CustomCommandPlanTestEffects {
    enum Outcome: Sendable {
        case success(String, delayMilliseconds: Int)
        case failure(String)
    }

    struct InjectedFailure: Error, LocalizedError, Sendable {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private let outcome: Outcome
    private var plans: [SignalCommandPlan] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func run(
        _ plan: SignalCommandPlan
    ) async throws -> SignalCustomCommandPlanTestResult {
        plans.append(plan)
        switch outcome {
        case .success(let message, let delayMilliseconds):
            if delayMilliseconds > 0 {
                try await ContinuousClock().sleep(
                    for: .milliseconds(delayMilliseconds)
                )
            }
            try Task.checkCancellation()
            return SignalCustomCommandPlanTestResult(
                succeeded: true,
                message: message
            )
        case .failure(let message):
            throw InjectedFailure(message: message)
        }
    }

    func callCount() -> Int {
        plans.count
    }

    func receivedPlans() -> [SignalCommandPlan] {
        plans
    }
}

private actor InMemoryCustomCommandRepository:
    SignalCustomCommandRepository
{
    private let document: SignalCommandDocument
    private let importedDocument: SignalCommandDocument?
    private var saved: SignalCommandDocument?
    private var exported: SignalCommandDocument?
    private var saves = 0
    private var exports = 0

    init(
        document: SignalCommandDocument,
        importedDocument: SignalCommandDocument? = nil
    ) {
        self.document = document
        self.importedDocument = importedDocument
    }

    func loadOrInstallDefaults() -> SignalCommandDocument {
        document
    }

    func save(_ document: SignalCommandDocument) {
        saved = document
        saves += 1
    }

    func importDocument(
        from source: URL
    ) throws -> SignalCommandDocument {
        importedDocument ?? document
    }

    func export(
        _ document: SignalCommandDocument,
        to destination: URL
    ) throws {
        exported = document
        exports += 1
    }

    func savedDocument() -> SignalCommandDocument? {
        saved
    }

    func saveCount() -> Int {
        saves
    }

    func exportedDocument() -> SignalCommandDocument? {
        exported
    }

    func exportCount() -> Int {
        exports
    }
}

@MainActor
private final class IdentifierSequence {
    private var value = 0

    func next() -> String {
        defer { value += 1 }
        return "id-\(value)"
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}

private func waitForTestCalls(
    _ expectedCount: Int,
    effects: CustomCommandPlanTestEffects
) async {
    for _ in 0..<200 {
        if await effects.callCount() >= expectedCount {
            return
        }
        await Task.yield()
    }
}
