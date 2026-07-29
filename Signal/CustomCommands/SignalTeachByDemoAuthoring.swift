import Foundation

public enum SignalTeachByDemoSessionState: Equatable, Sendable {
    case idle
    case capturing
    case reviewing
}

public struct SignalReviewedAccessibilityTarget: Equatable, Sendable {
    public var applicationBundleIdentifier: String
    public var role: String
    public var title: String
    public var identifier: String?
    public var isSecureField: Bool
    public var wasUserReviewed: Bool

    public init(
        applicationBundleIdentifier: String,
        role: String,
        title: String,
        identifier: String? = nil,
        isSecureField: Bool = false,
        wasUserReviewed: Bool
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.role = role
        self.title = title
        self.identifier = identifier
        self.isSecureField = isSecureField
        self.wasUserReviewed = wasUserReviewed
    }

    fileprivate var redactedForStorage: Self {
        guard isSecureField else { return self }
        return Self(
            applicationBundleIdentifier: applicationBundleIdentifier,
            role: role,
            title: "Secure field",
            identifier: nil,
            isSecureField: true,
            wasUserReviewed: wasUserReviewed
        )
    }
}

public enum SignalTeachByDemoModifier: String, CaseIterable, Sendable {
    case command
    case control
    case option
    case shift
    case function
}

public struct SignalTeachByDemoKeyCombo: Equatable, Sendable {
    public var key: String
    public var modifiers: Set<SignalTeachByDemoModifier>

    public init(key: String, modifiers: Set<SignalTeachByDemoModifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum SignalTeachByDemoProposalKind: Equatable, Sendable {
    case openHTTPSURL(String)
    case clickAccessibilityTarget(SignalReviewedAccessibilityTarget)
    case typeReviewedText(
        text: String,
        target: SignalReviewedAccessibilityTarget
    )
    case keyCombo(SignalTeachByDemoKeyCombo)
    case wait(milliseconds: Int)

    public var title: String {
        switch self {
        case .openHTTPSURL: "Open HTTPS URL"
        case .clickAccessibilityTarget: "Click reviewed target"
        case .typeReviewedText: "Type reviewed non-secret text"
        case .keyCombo: "Key combination"
        case .wait: "Wait"
        }
    }
}

public enum SignalTeachByDemoRuntimeSupport: Equatable, Sendable {
    case supported
    case unsupported(reason: String)
}

public struct SignalTeachByDemoProposal:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String
    public var kind: SignalTeachByDemoProposalKind
    public var runtimeSupport: SignalTeachByDemoRuntimeSupport
    public var isReviewed: Bool

    public init(
        id: String,
        kind: SignalTeachByDemoProposalKind,
        runtimeSupport: SignalTeachByDemoRuntimeSupport,
        isReviewed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.runtimeSupport = runtimeSupport
        self.isReviewed = isReviewed
    }
}

public enum SignalTeachByDemoError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case captureNotActive
    case reviewNotActive
    case targetNotReviewed
    case secureValueRedacted
    case invalidText
    case invalidKeyCombo
    case invalidWait
    case proposalNotFound
    case unreviewedProposal
    case unsupportedProposal(String)

    public var errorDescription: String? {
        switch self {
        case .captureNotActive:
            "Start capture before recording a proposed step."
        case .reviewNotActive:
            "Finish capture before applying reviewed proposals."
        case .targetNotReviewed:
            "Select and review the accessibility target before capture."
        case .secureValueRedacted:
            "Secure or secret input was redacted and was not recorded."
        case .invalidText:
            "Typed text must be non-secret reviewed text of at most 512 characters."
        case .invalidKeyCombo:
            "Key combinations require a safe key and at least one modifier."
        case .invalidWait:
            "Wait must be between 100 and 60000 milliseconds."
        case .proposalNotFound:
            "The proposed step no longer exists."
        case .unreviewedProposal:
            "Every proposed step must be reviewed."
        case .unsupportedProposal(let reason):
            reason
        }
    }
}

@MainActor
public final class SignalTeachByDemoModel: ObservableObject {
    @Published public private(set) var sessionState:
        SignalTeachByDemoSessionState = .idle
    @Published public private(set) var proposals: [SignalTeachByDemoProposal] = []
    @Published public private(set) var redactedEventCount = 0
    @Published public private(set) var notice: String = ""

    private let urlPolicy: SignalCommandURLPolicy
    private let safetyPolicy: SignalCustomCommandSafetyPolicy
    private let makeIdentifier: @MainActor () -> String

    public init(
        urlPolicy: SignalCommandURLPolicy = .init(),
        safetyPolicy: SignalCustomCommandSafetyPolicy = .init(),
        makeIdentifier: @escaping @MainActor () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.urlPolicy = urlPolicy
        self.safetyPolicy = safetyPolicy
        self.makeIdentifier = makeIdentifier
    }

    public var canApplyToRuntime: Bool {
        sessionState == .reviewing
            && !proposals.isEmpty
            && proposals.allSatisfy {
                $0.isReviewed && $0.runtimeSupport == .supported
            }
    }

    public func beginCapture() {
        proposals = []
        redactedEventCount = 0
        notice =
            "Capture records structured proposals only. It does not execute them."
        sessionState = .capturing
    }

    public func finishCaptureForReview() throws {
        guard sessionState == .capturing else {
            throw SignalTeachByDemoError.captureNotActive
        }
        sessionState = .reviewing
        notice =
            "Review every proposal. Unsupported proposals cannot be saved."
    }

    public func cancel() {
        proposals = []
        redactedEventCount = 0
        notice = ""
        sessionState = .idle
    }

    public func recordOpenHTTPSURL(_ rawURL: String) throws {
        try requireCapture()
        let url = try urlPolicy.validate(rawURL)
        append(
            .openHTTPSURL(url.absoluteString),
            support: .supported
        )
    }

    public func recordAccessibilityClick(
        target: SignalReviewedAccessibilityTarget
    ) throws {
        try requireCapture()
        guard target.wasUserReviewed else {
            throw SignalTeachByDemoError.targetNotReviewed
        }
        if target.isSecureField {
            redactSecureEvent()
            throw SignalTeachByDemoError.secureValueRedacted
        }
        append(
            .clickAccessibilityTarget(target.redactedForStorage),
            support: .unsupported(
                reason:
                    "Accessibility click is not in the current closed runtime schema."
            )
        )
    }

    public func recordTypedText(
        _ text: String,
        target: SignalReviewedAccessibilityTarget,
        isSecret: Bool
    ) throws {
        try requireCapture()
        guard target.wasUserReviewed else {
            throw SignalTeachByDemoError.targetNotReviewed
        }
        if isSecret || target.isSecureField || safetyPolicy.looksSensitive(text) {
            redactSecureEvent()
            throw SignalTeachByDemoError.secureValueRedacted
        }
        let reviewedText: String
        do {
            reviewedText = try safetyPolicy.validateAuthoringText(
                text,
                field: "Typed text",
                maximum: 512,
                permitsEmpty: false
            )
        } catch {
            throw SignalTeachByDemoError.invalidText
        }
        append(
            .typeReviewedText(
                text: reviewedText,
                target: target.redactedForStorage
            ),
            support: .unsupported(
                reason:
                    "Generic text entry is not in the current closed runtime schema."
            )
        )
    }

    public func recordKeyCombo(_ combo: SignalTeachByDemoKeyCombo) throws {
        try requireCapture()
        let key = combo.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              key.count <= 24,
              !combo.modifiers.isEmpty,
              !key.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw SignalTeachByDemoError.invalidKeyCombo
        }
        append(
            .keyCombo(.init(key: key, modifiers: combo.modifiers)),
            support: .unsupported(
                reason:
                    "Generic key combinations are not in the current closed runtime schema."
            )
        )
    }

    public func recordWait(milliseconds: Int) throws {
        try requireCapture()
        guard (100...60_000).contains(milliseconds) else {
            throw SignalTeachByDemoError.invalidWait
        }
        append(
            .wait(milliseconds: milliseconds),
            support: .unsupported(
                reason:
                    "A wait action is not in the current closed runtime schema."
            )
        )
    }

    public func setReviewed(_ reviewed: Bool, proposalID: String) throws {
        guard sessionState == .reviewing else {
            throw SignalTeachByDemoError.reviewNotActive
        }
        guard let index = proposals.firstIndex(where: { $0.id == proposalID })
        else {
            throw SignalTeachByDemoError.proposalNotFound
        }
        proposals[index].isReviewed = reviewed
    }

    public func deleteProposal(id: String) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else {
            return
        }
        proposals.remove(at: index)
    }

    public func moveProposal(id: String, to destinationIndex: Int) throws {
        guard let sourceIndex = proposals.firstIndex(where: { $0.id == id }),
              proposals.indices.contains(destinationIndex) else {
            throw SignalCustomCommandAuthoringError.invalidMove
        }
        guard sourceIndex != destinationIndex else { return }
        let proposal = proposals.remove(at: sourceIndex)
        proposals.insert(proposal, at: destinationIndex)
    }

    public func reviewedRuntimeSteps() throws
        -> [SignalCustomCommandStepDraft]
    {
        guard sessionState == .reviewing else {
            throw SignalTeachByDemoError.reviewNotActive
        }
        guard proposals.allSatisfy(\.isReviewed) else {
            throw SignalTeachByDemoError.unreviewedProposal
        }
        return try proposals.map { proposal in
            switch proposal.runtimeSupport {
            case .supported:
                break
            case .unsupported(let reason):
                throw SignalTeachByDemoError.unsupportedProposal(reason)
            }
            switch proposal.kind {
            case .openHTTPSURL(let url):
                return SignalCustomCommandStepDraft(
                    id: "signal.custom.fist.step-\(makeIdentifier())",
                    action: .openHTTPSURL(url)
                )
            case .clickAccessibilityTarget,
                 .typeReviewedText,
                 .keyCombo,
                 .wait:
                throw SignalTeachByDemoError.unsupportedProposal(
                    "The proposal cannot be represented by the current runtime schema."
                )
            }
        }
    }

    private func requireCapture() throws {
        guard sessionState == .capturing else {
            throw SignalTeachByDemoError.captureNotActive
        }
    }

    private func append(
        _ kind: SignalTeachByDemoProposalKind,
        support: SignalTeachByDemoRuntimeSupport
    ) {
        proposals.append(
            SignalTeachByDemoProposal(
                id: "signal.demo.proposal-\(makeIdentifier())",
                kind: kind,
                runtimeSupport: support
            )
        )
    }

    private func redactSecureEvent() {
        redactedEventCount += 1
        notice =
            "A password, secure field, or secret-like value was omitted from capture."
    }
}
