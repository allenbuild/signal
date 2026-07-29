import SwiftUI

@MainActor
public struct SignalTeachByDemoRecordingPanel: View {
    @ObservedObject private var bridge: SignalTeachByDemoRecordingBridge
    @ObservedObject private var proposalModel: SignalTeachByDemoModel
    private let startAllowed: Bool
    private let useReviewedSteps:
        @MainActor ([SignalCustomCommandStepDraft]) -> Void

    public init(
        bridge: SignalTeachByDemoRecordingBridge,
        startAllowed: Bool = true,
        useReviewedSteps:
            @escaping @MainActor ([SignalCustomCommandStepDraft]) -> Void
    ) {
        self.bridge = bridge
        proposalModel = bridge.proposalModel
        self.startAllowed = startAllowed
        self.useReviewedSteps = useReviewedSteps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            timing
            controls

            if bridge.redactionCount > 0 {
                Label(
                    "\(bridge.redactionCount) secure input event(s) redacted",
                    systemImage: "eye.slash.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .accessibilityHint(
                    "No secure keystroke or field value was retained."
                )
            }

            if let errorMessage = bridge.errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.red)
            }

            if proposalModel.sessionState == .reviewing {
                reviewSection
            } else {
                captureExplanation
            }
        }
        .padding(18)
        .frame(minWidth: 410, minHeight: 500)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bridge.isRecording ? Color.red : Color.secondary)
                .frame(width: 12, height: 12)
                .shadow(
                    color: bridge.isRecording
                        ? Color.red.opacity(0.45)
                        : .clear,
                    radius: 5
                )
                .accessibilityLabel(
                    bridge.isRecording ? "Recording" : "Not recording"
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    bridge.isRecording
                        ? "Recording Teach by Demo"
                        : phaseTitle
                )
                .font(.title3.bold())
                Text(
                    "Local structured proposals only—no upload or raw replay."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.durationText(bridge.elapsed))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .accessibilityLabel("Elapsed recording time")
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(
                value: min(bridge.elapsed, bridge.hardDurationLimit),
                total: max(bridge.hardDurationLimit, 1)
            )
            HStack {
                Text(
                    "Recommended \(Self.durationText(bridge.recommendedDuration))"
                )
                if bridge.hasReachedRecommendedDuration, bridge.isRecording {
                    Text("Recommended length reached")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(
                    "Hard stop \(Self.durationText(bridge.hardDurationLimit))"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if bridge.isRecording {
                Button("Stop & Review") {
                    bridge.stop()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") {
                    bridge.cancel()
                }
                Button("Emergency Cancel", role: .destructive) {
                    bridge.emergencyCancel()
                }
            } else {
                Button(
                    proposalModel.sessionState == .reviewing
                        ? "Start New Capture"
                        : "Start Capture"
                ) {
                    bridge.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!startAllowed)
                if !startAllowed {
                    Label(
                        "Review an app and target or URL before capture",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var captureExplanation: some View {
        GroupBox("Capture boundary") {
            VStack(alignment: .leading, spacing: 7) {
                Label(
                    "Start is always explicit",
                    systemImage: "hand.tap"
                )
                Label(
                    "Only reviewed apps, accessibility targets, and HTTPS URLs become proposals",
                    systemImage: "checkmark.shield"
                )
                Label(
                    "Passwords, secure fields, and secure-input keystrokes become a count only",
                    systemImage: "eye.slash"
                )
                Label(
                    "Pointer coordinates are never retained as replay actions",
                    systemImage: "scope"
                )
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review every proposal")
                    .font(.headline)
                Spacer()
                Text("\(proposalModel.proposals.count) proposal(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(
                    Array(proposalModel.proposals.enumerated()),
                    id: \.element.id
                ) { index, proposal in
                    proposalRow(proposal, at: index)
                }
            }
            .overlay {
                if proposalModel.proposals.isEmpty {
                    VStack(spacing: 7) {
                        Label(
                            "No proposals captured",
                            systemImage: "rectangle.and.pencil.and.ellipsis"
                        )
                        .font(.headline)
                        Text(
                            "Start a new capture after reviewing the allowed context."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Use reviewed supported steps") {
                guard let steps = bridge.reviewedRuntimeSteps() else {
                    return
                }
                useReviewedSteps(steps)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!bridge.canUseReviewedSteps)

            Text(
                "Unsupported proposals stay visible for review but cannot be converted or saved."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func proposalRow(
        _ proposal: SignalTeachByDemoProposal,
        at index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(index + 1). \(proposal.kind.title)")
                    .font(.headline)
                Spacer()
                supportLabel(proposal.runtimeSupport)
            }
            proposalSummary(proposal.kind)
            if case .unsupported(let reason) = proposal.runtimeSupport {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle(
                "I reviewed this proposal",
                isOn: Binding(
                    get: { proposal.isReviewed },
                    set: {
                        bridge.setReviewed(
                            $0,
                            proposalID: proposal.id
                        )
                    }
                )
            )
            HStack {
                Button("Up") {
                    bridge.moveProposal(
                        id: proposal.id,
                        to: index - 1
                    )
                }
                .disabled(index == 0)
                Button("Down") {
                    bridge.moveProposal(
                        id: proposal.id,
                        to: index + 1
                    )
                }
                .disabled(index + 1 == proposalModel.proposals.count)
                Button("Delete", role: .destructive) {
                    bridge.deleteProposal(id: proposal.id)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func supportLabel(
        _ support: SignalTeachByDemoRuntimeSupport
    ) -> some View {
        switch support {
        case .supported:
            Label("Supported", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .unsupported:
            Label("Unsupported", systemImage: "nosign")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func proposalSummary(
        _ proposal: SignalTeachByDemoProposalKind
    ) -> some View {
        switch proposal {
        case .openHTTPSURL(let url):
            Text(url)
        case .clickAccessibilityTarget(let target):
            Text(
                "\(target.applicationBundleIdentifier) · \(target.role) · \(target.title)"
            )
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

    private var phaseTitle: String {
        switch bridge.captureState.phase {
        case .idle: "Teach by Demo"
        case .recording: "Recording Teach by Demo"
        case .stopped: "Capture stopped—review required"
        case .cancelled: "Capture cancelled"
        case .failed: "Capture unavailable"
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
