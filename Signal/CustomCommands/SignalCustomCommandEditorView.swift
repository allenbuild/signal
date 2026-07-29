import SwiftUI

@MainActor
public struct SignalCustomCommandEditorView: View {
    @ObservedObject private var model: SignalCustomCommandEditorModel
    @ObservedObject private var demoModel: SignalTeachByDemoModel
    private let recordingBridge: SignalTeachByDemoRecordingBridge?
    private let recordingSetup:
        SignalTeachByDemoRecordingSetupModel?
    private let filePicker: any SignalCustomCommandFileChoosing
    @State private var naturalLanguageDraft = ""
    @State private var showDraftGrammar = false
    @State private var confirmsReset = false

    public init(
        model: SignalCustomCommandEditorModel,
        demoModel: SignalTeachByDemoModel,
        recordingBridge: SignalTeachByDemoRecordingBridge? = nil,
        recordingSetup: SignalTeachByDemoRecordingSetupModel? = nil,
        filePicker: any SignalCustomCommandFileChoosing =
            SignalCustomCommandSystemFilePicker()
    ) {
        self.model = model
        self.demoModel = demoModel
        self.recordingBridge = recordingBridge
        self.recordingSetup = recordingSetup
        self.filePicker = filePicker
    }

    public var body: some View {
        HSplitView {
            editor
                .frame(minWidth: 520)
            recordingPane
                .frame(minWidth: 410)
        }
        .frame(minWidth: 960, minHeight: 720)
        .alert(
            "Reset Fist to its unconfigured default?",
            isPresented: $confirmsReset
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Fist", role: .destructive) {
                model.resetFistToDefault()
            }
        } message: {
            Text(
                "The seven fixed commands remain unchanged. Review and save are still required."
            )
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fist custom command")
                        .font(.title2.bold())
                    Text("Closed-schema actions only. Review is required before save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Load Local") {
                    Task {
                        try? await model.load()
                    }
                }
                Button("Import Fist…") {
                    guard let source = filePicker.chooseImportURL()
                    else { return }
                    Task {
                        try? await model.importFist(from: source)
                    }
                }
                Button("Export Saved…") {
                    guard let destination =
                        filePicker.chooseExportURL(
                            suggestedFilename:
                                "signal-commands.json"
                        ) else {
                        return
                    }
                    Task {
                        try? await model.exportSavedDocument(
                            to: destination
                        )
                    }
                }
                .disabled(model.hasUnsavedChanges)
                Button("Reset Fist…", role: .destructive) {
                    confirmsReset = true
                }
            }

            DisclosureGroup(
                "Constrained natural-language draft",
                isExpanded: $showDraftGrammar
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(
                        "Local deterministic grammar: name:, description:, open: public HTTPS, bolt: reviewed prompt, and spotify: next."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextEditor(text: $naturalLanguageDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 95)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        }
                        .accessibilityLabel(
                            "Constrained natural-language command draft"
                        )
                    Button("Create Draft for Review") {
                        _ = try? model.applyNaturalLanguageDraft(
                            naturalLanguageDraft
                        )
                    }
                    Text(
                        "No model, network request, shell, AppleScript, filesystem action, or executable is available to this parser."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            TextField(
                "Command name",
                text: Binding(
                    get: { model.name },
                    set: { model.setName($0) }
                )
            )
            TextEditor(
                text: Binding(
                    get: { model.details },
                    set: { model.setDetails($0) }
                )
            )
            .frame(height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }
            .accessibilityLabel("Command description")

            HStack {
                Text("Ordered allowlisted steps")
                    .font(.headline)
                Spacer()
                Menu("Add step") {
                    Button("Open HTTPS URL") {
                        model.addStep(
                            action: .openHTTPSURL("https://example.com")
                        )
                    }
                    Button("Submit reviewed Bolt prompt") {
                        model.addStep(action: .boltPrompt(""))
                    }
                    Button("Next Spotify track") {
                        model.addStep(action: .spotifyNextTrack)
                    }
                }
            }

            List {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) {
                    index,
                    step in
                    SignalCustomCommandStepRow(
                        index: index,
                        step: step,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < model.steps.count,
                        update: { model.updateStep($0) },
                        moveUp: {
                            try? model.moveStep(
                                id: step.id,
                                to: index - 1
                            )
                        },
                        moveDown: {
                            try? model.moveStep(
                                id: step.id,
                                to: index + 1
                            )
                        },
                        delete: {
                            model.deleteStep(id: step.id)
                        }
                    )
                }
            }
            .overlay {
                if model.steps.isEmpty {
                    VStack(spacing: 8) {
                        Label(
                            "No command steps",
                            systemImage: "list.bullet.rectangle"
                        )
                        .font(.headline)
                        Text(
                            "Add an allowlisted action, or use Reset Fist for the reviewed unconfigured default."
                        )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Preview Validation (Does Not Run)") {
                    _ = model.previewValidation()
                }
                if let preview = model.validationPreview {
                    Label(
                        preview.summary,
                        systemImage: preview.isValid
                            ? "checkmark.shield"
                            : "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        preview.isValid ? .green : .red
                    )
                }
            }

            if let preview = model.validationPreview {
                GroupBox("Non-executing validation preview") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            preview.willExecute
                                ? "Execution enabled"
                                : "No actions will execute"
                        )
                        .font(.headline)
                        ForEach(
                            Array(
                                preview.orderedActionTitles.enumerated()
                            ),
                            id: \.offset
                        ) { index, title in
                            Text("\(index + 1). \(title)")
                        }
                        ForEach(
                            Array(preview.messages.enumerated()),
                            id: \.offset
                        ) { _, message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let review = model.review {
                GroupBox("Review before save") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(review.name).font(.headline)
                        if !review.details.isEmpty {
                            Text(review.details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            review.isUnconfigured
                                ? "Unconfigured default · no runtime plan"
                                : "\(review.orderedSteps.count) ordered step(s)"
                        )
                            .font(.caption)
                        Text(
                            "Saving changes only the configurable Fist command."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                phaseLabel
                testStateLabel
                if let operationMessage = model.operationMessage {
                    Text(operationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if model.phase == .reviewing {
                    Button("Back to editing") {
                        model.resumeEditing()
                    }
                    if model.testState.isTesting {
                        Button("Cancel Test", role: .destructive) {
                            model.cancelTest()
                        }
                    } else {
                        Button("Test reviewed command") {
                            Task {
                                try? await model.testReviewed()
                            }
                        }
                        .disabled(!model.canTestReviewedDraft)
                    }
                    Button("Save reviewed command") {
                        Task {
                            try? await model.saveReviewed()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSaveReviewedDraft)
                } else {
                    Button("Review command") {
                        _ = try? model.beginReview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var recordingPane: some View {
        if let recordingBridge, let recordingSetup {
            SignalTeachByDemoAuthorizedRecordingPane(
                bridge: recordingBridge,
                setup: recordingSetup,
                useReviewedSteps: { steps in
                    model.replaceSteps(with: steps)
                }
            )
        } else {
            SignalTeachByDemoView(
                model: demoModel,
                applyReviewedSteps: applyReviewedDemo
            )
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch model.phase {
        case .unloaded:
            Label("Not loaded", systemImage: "tray")
        case .editing:
            Label("Editing", systemImage: "pencil")
        case .reviewing:
            Label("Awaiting reviewed save", systemImage: "checklist")
        case .saving:
            ProgressView("Saving")
        case .saved:
            Label("Saved locally", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var testStateLabel: some View {
        switch model.testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView("Testing")
                .controlSize(.small)
        case .succeeded:
            Label("Test succeeded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Test failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Label("Test cancelled", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func applyReviewedDemo() {
        guard let steps = try? demoModel.reviewedRuntimeSteps() else {
            return
        }
        model.replaceSteps(with: steps)
    }
}

@MainActor
private struct SignalTeachByDemoAuthorizedRecordingPane: View {
    @ObservedObject var bridge: SignalTeachByDemoRecordingBridge
    @ObservedObject var setup: SignalTeachByDemoRecordingSetupModel
    let useReviewedSteps:
        @MainActor ([SignalCustomCommandStepDraft]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SignalTeachByDemoRecordingSetupPanel(model: setup)
                SignalTeachByDemoRecordingPanel(
                    bridge: bridge,
                    startAllowed: setup.isReadyToStart,
                    useReviewedSteps: useReviewedSteps
                )
            }
            .padding(14)
        }
    }
}

@MainActor
private struct SignalCustomCommandStepRow: View {
    let index: Int
    let step: SignalCustomCommandStepDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: @MainActor (SignalCustomCommandStepDraft) -> Void
    let moveUp: @MainActor () -> Void
    let moveDown: @MainActor () -> Void
    let delete: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index + 1). \(step.action.title)")
                    .font(.headline)
                Spacer()
                Button {
                    moveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move step up")
                Button {
                    moveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move step down")
                Button(role: .destructive) {
                    delete()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete step")
            }

            switch step.action {
            case .openHTTPSURL(let url):
                TextField(
                    "https://…",
                    text: Binding(
                        get: { url },
                        set: { replacement in
                            var edited = step
                            edited.action = .openHTTPSURL(replacement)
                            update(edited)
                        }
                    )
                )
            case .boltPrompt(let prompt):
                TextField(
                    "Reviewed non-secret prompt",
                    text: Binding(
                        get: { prompt },
                        set: { replacement in
                            var edited = step
                            edited.action = .boltPrompt(replacement)
                            update(edited)
                        }
                    )
                )
            case .spotifyNextTrack:
                Text(
                    "Typed Spotify-next action; no script or executable."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Stepper(
                    "Timeout: \(step.timeoutMilliseconds) ms",
                    value: Binding(
                        get: { step.timeoutMilliseconds },
                        set: { replacement in
                            var edited = step
                            edited.timeoutMilliseconds = replacement
                            update(edited)
                        }
                    ),
                    in: 100...60_000,
                    step: 100
                )
                Picker(
                    "On failure",
                    selection: Binding(
                        get: { step.failurePolicy },
                        set: { replacement in
                            var edited = step
                            edited.failurePolicy = replacement
                            update(edited)
                        }
                    )
                ) {
                    Text("Stop").tag(SignalCommandFailurePolicy.stop)
                    Text("Continue").tag(SignalCommandFailurePolicy.continue)
                }
                .frame(width: 170)
            }
            .font(.caption)
        }
        .padding(.vertical, 5)
    }
}

@MainActor
public struct SignalTeachByDemoView: View {
    @ObservedObject private var model: SignalTeachByDemoModel
    private let applyReviewedSteps: @MainActor () -> Void

    public init(
        model: SignalTeachByDemoModel,
        applyReviewedSteps: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.applyReviewedSteps = applyReviewedSteps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Teach by Demo")
                .font(.title2.bold())
            Text(
                "Capture stores high-level proposals only. It never executes actions."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                switch model.sessionState {
                case .idle:
                    Button("Start proposal capture") {
                        model.beginCapture()
                    }
                        .buttonStyle(.borderedProminent)
                case .capturing:
                    Label("Capturing proposals", systemImage: "record.circle")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Finish & Review") {
                        try? model.finishCaptureForReview()
                    }
                case .reviewing:
                    Label("Review required", systemImage: "checklist")
                    Spacer()
                    Button("Discard", role: .destructive) {
                        model.cancel()
                    }
                }
            }

            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.redactedEventCount > 0 {
                Label(
                    "\(model.redactedEventCount) secure event(s) omitted",
                    systemImage: "eye.slash.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            List {
                ForEach(Array(model.proposals.enumerated()), id: \.element.id) {
                    index,
                    proposal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(index + 1). \(proposal.kind.title)")
                                .font(.headline)
                            Spacer()
                            supportLabel(proposal.runtimeSupport)
                        }
                        proposalDetail(proposal.kind)
                        if model.sessionState == .reviewing {
                            Toggle(
                                "I reviewed this proposal",
                                isOn: Binding(
                                    get: { proposal.isReviewed },
                                    set: {
                                        try? model.setReviewed(
                                            $0,
                                            proposalID: proposal.id
                                        )
                                    }
                                )
                            )
                            HStack {
                                Button("Up") {
                                    try? model.moveProposal(
                                        id: proposal.id,
                                        to: index - 1
                                    )
                                }
                                .disabled(index == 0)
                                Button("Down") {
                                    try? model.moveProposal(
                                        id: proposal.id,
                                        to: index + 1
                                    )
                                }
                                .disabled(index + 1 == model.proposals.count)
                                Button("Delete", role: .destructive) {
                                    model.deleteProposal(id: proposal.id)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .overlay {
                if model.proposals.isEmpty {
                    VStack(spacing: 8) {
                        Label(
                            "No proposals",
                            systemImage: "rectangle.and.pencil.and.ellipsis"
                        )
                        .font(.headline)
                        Text(
                            "A capture adapter may add only structured, reviewed events."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Use reviewed supported steps") {
                applyReviewedSteps()
            }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApplyToRuntime)

            Text(
                "Click, generic text, key-combination, and wait proposals are visible but cannot be saved because the current closed runtime schema does not support them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    @ViewBuilder
    private func supportLabel(
        _ support: SignalTeachByDemoRuntimeSupport
    ) -> some View {
        switch support {
        case .supported:
            Label("Savable", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .unsupported:
            Label("Unsupported", systemImage: "nosign")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func proposalDetail(
        _ proposal: SignalTeachByDemoProposalKind
    ) -> some View {
        switch proposal {
        case .openHTTPSURL(let url):
            Text(url)
        case .clickAccessibilityTarget(let target):
            Text("\(target.applicationBundleIdentifier) · \(target.role) · \(target.title)")
        case .typeReviewedText(let text, let target):
            Text("“\(text)” → \(target.role) \(target.title)")
        case .keyCombo(let combo):
            Text(
                (combo.modifiers.map(\.rawValue).sorted() + [combo.key])
                    .joined(separator: " + ")
            )
        case .wait(let milliseconds):
            Text("\(milliseconds) ms")
        }
    }
}
