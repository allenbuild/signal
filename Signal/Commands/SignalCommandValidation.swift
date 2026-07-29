import Foundation

public struct SignalCommandValidator: Sendable {
    public static let maximumImportBytes = 1_048_576

    private let urlPolicy: SignalCommandURLPolicy

    public init(urlPolicy: SignalCommandURLPolicy = .init()) {
        self.urlPolicy = urlPolicy
    }

    public func validate(_ document: SignalCommandDocument) throws {
        guard document.schemaVersion == SignalCommandDocument.currentSchemaVersion else {
            throw SignalCommandValidationError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard document.catalogVersion == SignalCommandDocument.currentCatalogVersion else {
            throw SignalCommandValidationError.unsupportedCatalogVersion(document.catalogVersion)
        }
        try validateIdentifier(document.profile.id, path: "profile.id")
        try validateText(document.profile.name, maximum: 100, path: "profile.name")

        let commands = document.profile.commands
        guard commands.count == SignalCommandGesture.allCases.count else {
            throw SignalCommandValidationError.invalidField(
                path: "profile.commands",
                reason: "exactly eight commands are required"
            )
        }

        var commandIDs: Set<String> = []
        var gestures: Set<SignalCommandGesture> = []
        for (index, command) in commands.enumerated() {
            let path = "profile.commands[\(index)]"
            try validateIdentifier(command.id, path: "\(path).id")
            guard commandIDs.insert(command.id).inserted else {
                throw SignalCommandValidationError.duplicateIdentifier(command.id)
            }
            guard gestures.insert(command.gesture).inserted else {
                throw SignalCommandValidationError.duplicateGesture(command.gesture)
            }
            try validateText(command.name, maximum: 80, path: "\(path).name")
            try validateText(
                command.details,
                maximum: 500,
                path: "\(path).details",
                permitsEmpty: true
            )
            guard command.isConfigurable == (command.gesture == .fist) else {
                throw SignalCommandValidationError.invalidField(
                    path: "\(path).isConfigurable",
                    reason: "only Fist is configurable"
                )
            }
            if command.gesture != .fist, command.plan == nil {
                throw SignalCommandValidationError.invalidField(
                    path: "\(path).plan",
                    reason: "fixed commands require a plan"
                )
            }
            if let plan = command.plan {
                try validate(plan, path: "\(path).plan")
            }
            if command.gesture != .fist {
                guard let canonical =
                    SignalDefaultCommandCatalog.document.profile[command.gesture],
                    command == canonical
                else {
                    throw SignalCommandValidationError.invalidField(
                        path: path,
                        reason: "fixed command definitions cannot be modified"
                    )
                }
            }
        }

        for gesture in SignalCommandGesture.allCases where !gestures.contains(gesture) {
            throw SignalCommandValidationError.missingGesture(gesture)
        }
        guard commands.map(\.gesture) == SignalCommandGesture.allCases else {
            throw SignalCommandValidationError.invalidField(
                path: "profile.commands",
                reason: "commands must remain in canonical gesture order"
            )
        }
    }

    public func validate(_ plan: SignalCommandPlan) throws {
        try validate(plan, path: "plan")
    }

    public func validateClosedJSON(_ data: Data) throws {
        guard data.count <= Self.maximumImportBytes,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw SignalCommandValidationError.malformedJSON
        }
        try requireKeys(
            root,
            allowed: ["schemaVersion", "catalogVersion", "profile"],
            path: "$"
        )
        guard let profile = root["profile"] as? [String: Any] else {
            throw SignalCommandValidationError.malformedJSON
        }
        try requireKeys(profile, allowed: ["id", "name", "commands"], path: "$.profile")
        guard let commands = profile["commands"] as? [[String: Any]] else {
            throw SignalCommandValidationError.malformedJSON
        }
        for (commandIndex, command) in commands.enumerated() {
            let commandPath = "$.profile.commands[\(commandIndex)]"
            try requireKeys(
                command,
                allowed: ["id", "gesture", "name", "details", "isConfigurable", "plan"],
                required: ["id", "gesture", "name", "details", "isConfigurable"],
                path: commandPath
            )
            guard let encodedPlan = command["plan"] else { continue }
            if encodedPlan is NSNull { continue }
            guard let plan = command["plan"] as? [String: Any] else {
                throw SignalCommandValidationError.malformedJSON
            }
            try requireKeys(
                plan,
                allowed: ["id", "steps", "timeoutMilliseconds"],
                path: "\(commandPath).plan"
            )
            guard let steps = plan["steps"] as? [[String: Any]] else {
                throw SignalCommandValidationError.malformedJSON
            }
            for (stepIndex, step) in steps.enumerated() {
                let stepPath = "\(commandPath).plan.steps[\(stepIndex)]"
                try requireKeys(
                    step,
                    allowed: ["id", "action", "timeoutMilliseconds", "failurePolicy"],
                    path: stepPath
                )
                guard let action = step["action"] as? [String: Any],
                      let type = action["type"] as? String,
                      let parameters = action["parameters"] as? [String: Any]
                else {
                    throw SignalCommandValidationError.malformedJSON
                }
                try requireKeys(action, allowed: ["type", "parameters"], path: "\(stepPath).action")
                let parameterKeys: Set<String>
                switch type {
                case SignalCommandAction.Kind.openURL.rawValue:
                    parameterKeys = ["url"]
                case SignalCommandAction.Kind.boltPrompt.rawValue:
                    parameterKeys = ["prompt"]
                case SignalCommandAction.Kind.spotifyNextTrack.rawValue:
                    parameterKeys = []
                default:
                    throw SignalCommandValidationError.invalidField(
                        path: "\(stepPath).action.type",
                        reason: "unknown action \(type)"
                    )
                }
                try requireKeys(
                    parameters,
                    allowed: parameterKeys,
                    path: "\(stepPath).action.parameters"
                )
            }
        }
    }

    private func validate(_ plan: SignalCommandPlan, path: String) throws {
        try validateIdentifier(plan.id, path: "\(path).id")
        guard !plan.steps.isEmpty, plan.steps.count <= 50 else {
            throw SignalCommandValidationError.invalidField(
                path: "\(path).steps",
                reason: "one to fifty steps are required"
            )
        }
        guard (100...300_000).contains(plan.timeoutMilliseconds) else {
            throw SignalCommandValidationError.invalidField(
                path: "\(path).timeoutMilliseconds",
                reason: "must be between 100 and 300000"
            )
        }

        var stepIDs: Set<String> = []
        for (index, step) in plan.steps.enumerated() {
            let stepPath = "\(path).steps[\(index)]"
            try validateIdentifier(step.id, path: "\(stepPath).id")
            guard stepIDs.insert(step.id).inserted else {
                throw SignalCommandValidationError.duplicateIdentifier(step.id)
            }
            guard (100...60_000).contains(step.timeoutMilliseconds) else {
                throw SignalCommandValidationError.invalidField(
                    path: "\(stepPath).timeoutMilliseconds",
                    reason: "must be between 100 and 60000"
                )
            }
            switch step.action {
            case .openURL(let payload):
                _ = try urlPolicy.validate(payload.url)
            case .boltPrompt(let payload):
                try validateText(
                    payload.prompt,
                    maximum: 512,
                    path: "\(stepPath).action.parameters.prompt"
                )
                guard payload.prompt == SignalDefaultCommandCatalog.boltPrompt else {
                    throw SignalCommandValidationError.invalidField(
                        path: "\(stepPath).action.parameters.prompt",
                        reason: "must equal the reviewed built-in Bolt prompt"
                    )
                }
            case .spotifyNextTrack:
                break
            }
        }
    }

    private func validateIdentifier(_ value: String, path: String) throws {
        guard !value.isEmpty,
              value.count <= 128,
              value.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
                      .contains($0)
              })
        else {
            throw SignalCommandValidationError.invalidField(
                path: path,
                reason: "must be a nonempty safe identifier of at most 128 characters"
            )
        }
    }

    private func validateText(
        _ value: String,
        maximum: Int,
        path: String,
        permitsEmpty: Bool = false
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (permitsEmpty || !trimmed.isEmpty),
              value.count <= maximum,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw SignalCommandValidationError.invalidField(
                path: path,
                reason: "must contain safe text of at most \(maximum) characters"
            )
        }
    }

    private func requireKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        required: Set<String>? = nil,
        path: String
    ) throws {
        if let field = Set(object.keys).subtracting(allowed).sorted().first {
            throw SignalCommandValidationError.unexpectedJSONField(path: path, field: field)
        }
        if !(required ?? allowed).isSubset(of: Set(object.keys)) {
            throw SignalCommandValidationError.malformedJSON
        }
    }
}
