import Foundation

public struct SignalCustomCommandNaturalLanguageDraft:
    Equatable,
    Sendable
{
    public var name: String
    public var details: String
    public var orderedSteps: [SignalCustomCommandStepDraft]

    public init(
        name: String,
        details: String,
        orderedSteps: [SignalCustomCommandStepDraft]
    ) {
        self.name = name
        self.details = details
        self.orderedSteps = orderedSteps
    }
}

public enum SignalCustomCommandNaturalLanguageError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case emptyInput
    case duplicateField(String)
    case missingName
    case missingDescription
    case missingSteps
    case unknownInstruction(line: Int)
    case unsafeInstruction(line: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter a constrained command draft."
        case .duplicateField(let field):
            "The \(field) field may appear only once."
        case .missingName:
            "Add one “name:” line."
        case .missingDescription:
            "Add one “description:” line."
        case .missingSteps:
            "Add at least one allowlisted action line."
        case .unknownInstruction(let line):
            "Line \(line) is not in the constrained draft grammar."
        case .unsafeInstruction(let line):
            "Line \(line) contains prohibited or secret-like text."
        }
    }
}

/// Deterministic, local parser for a deliberately small line-oriented grammar:
///
///     name: My command
///     description: What the reviewed command does
///     open: https://public.example/path
///     bolt: reviewed non-secret prompt
///     spotify: next
///
/// It performs no network or model call and cannot produce shell, AppleScript,
/// executable, privilege, filesystem, or arbitrary automation actions.
public struct SignalCustomCommandNaturalLanguageParser: Sendable {
    private let urlPolicy: SignalCommandURLPolicy
    private let safetyPolicy: SignalCustomCommandSafetyPolicy

    public init(
        urlPolicy: SignalCommandURLPolicy = .init(),
        safetyPolicy: SignalCustomCommandSafetyPolicy = .init()
    ) {
        self.urlPolicy = urlPolicy
        self.safetyPolicy = safetyPolicy
    }

    public func parse(
        _ input: String
    ) throws -> SignalCustomCommandNaturalLanguageDraft {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw SignalCustomCommandNaturalLanguageError.emptyInput
        }

        let lines = input.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        var name: String?
        var details: String?
        var steps: [SignalCustomCommandStepDraft] = []

        for (zeroBasedIndex, rawLine) in lines.enumerated() {
            let lineNumber = zeroBasedIndex + 1
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !line.isEmpty else { continue }

            if let value = value(after: "name:", in: line) {
                guard name == nil else {
                    throw SignalCustomCommandNaturalLanguageError
                        .duplicateField("name")
                }
                name = try validate(
                    value,
                    field: "Name",
                    maximum: 80,
                    line: lineNumber
                )
                continue
            }
            if let value = value(after: "description:", in: line) {
                guard details == nil else {
                    throw SignalCustomCommandNaturalLanguageError
                        .duplicateField("description")
                }
                details = try validate(
                    value,
                    field: "Description",
                    maximum: 500,
                    line: lineNumber
                )
                continue
            }
            if let value = value(after: "open:", in: line) {
                let url = try urlPolicy.validate(value)
                steps.append(
                    makeStep(
                        index: steps.count,
                        action: .openHTTPSURL(url.absoluteString)
                    )
                )
                continue
            }
            if let value = value(after: "bolt:", in: line) {
                let prompt = try validate(
                    value,
                    field: "Bolt prompt",
                    maximum: 512,
                    line: lineNumber
                )
                steps.append(
                    makeStep(
                        index: steps.count,
                        action: .boltPrompt(prompt),
                        timeoutMilliseconds: 20_000
                    )
                )
                continue
            }
            if line.caseInsensitiveCompare("spotify: next")
                == .orderedSame {
                steps.append(
                    makeStep(
                        index: steps.count,
                        action: .spotifyNextTrack,
                        timeoutMilliseconds: 15_000
                    )
                )
                continue
            }

            throw SignalCustomCommandNaturalLanguageError
                .unknownInstruction(line: lineNumber)
        }

        guard let name else {
            throw SignalCustomCommandNaturalLanguageError.missingName
        }
        guard let details else {
            throw SignalCustomCommandNaturalLanguageError.missingDescription
        }
        guard !steps.isEmpty else {
            throw SignalCustomCommandNaturalLanguageError.missingSteps
        }
        guard steps.count <= 50 else {
            throw SignalCustomCommandAuthoringError.invalidStepCount
        }
        return SignalCustomCommandNaturalLanguageDraft(
            name: name,
            details: details,
            orderedSteps: steps
        )
    }

    private func value(
        after prefix: String,
        in line: String
    ) -> String? {
        guard line.lowercased().hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(
        _ value: String,
        field: String,
        maximum: Int,
        line: Int
    ) throws -> String {
        do {
            return try safetyPolicy.validateAuthoringText(
                value,
                field: field,
                maximum: maximum,
                permitsEmpty: false
            )
        } catch {
            throw SignalCustomCommandNaturalLanguageError
                .unsafeInstruction(line: line)
        }
    }

    private func makeStep(
        index: Int,
        action: SignalCustomCommandDraftAction,
        timeoutMilliseconds: Int = 10_000
    ) -> SignalCustomCommandStepDraft {
        SignalCustomCommandStepDraft(
            id: "signal.custom.fist.nl.step-\(index + 1)",
            action: action,
            timeoutMilliseconds: timeoutMilliseconds
        )
    }
}
