import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case openApplication = "open_application"
    case openURL = "open_url"
    case openDeepLink = "open_deep_link"
    case keyboardShortcut = "keyboard_shortcut"
    case typeText = "type_text"
    case wait
    case showNotification = "show_notification"
    case speakText = "speak_text"
    case playSound = "play_sound"
    case setClipboard = "set_clipboard"
    case readClipboardAndTransform = "read_clipboard_and_transform"
    case runAppleShortcut = "run_apple_shortcut"
    case runAppleScriptTemplate = "run_applescript_template"
    case httpRequest = "http_request"
    case discordWebhook = "discord_webhook"
    case slackWebhook = "slack_webhook"
    case mediaControl = "media_control"
    case setVolume = "set_volume"
    case showOverlay = "show_overlay"
    case focusApplication = "focus_application"
    case clickScreenPoint = "click_screen_point"
    case scrollAmount = "scroll_amount"
    case zoomSteps = "zoom_steps"
    case conditional
    case rawAppleScript = "raw_applescript"
    case shellCommand = "shell_command"

    public var isAdvanced: Bool {
        self == .rawAppleScript || self == .shellCommand
    }
}

public enum FailurePolicy: String, Codable, Sendable {
    case stop
    case `continue`
    case ask
}

public enum PlanSource: String, Codable, Sendable {
    case visual
    case naturalLanguage = "natural_language"
    case demoRecording = "demo_recording"
    case `import`
}

public enum ConfirmationMode: String, Codable, Sendable {
    case none
    case firstRun = "first_run"
    case everyRun = "every_run"
}

public struct Confirmation: Codable, Equatable, Sendable {
    public var mode: ConfirmationMode
    public var reason: String

    public init(mode: ConfirmationMode = .none, reason: String = "") {
        self.mode = mode
        self.reason = reason
    }

    public var isRequired: Bool { mode != .none }
}

public enum SecretProvider: String, Codable, Sendable {
    case discord
    case slack
    case httpBearer = "http_bearer"
    case httpBasic = "http_basic"
    case httpAPIKey = "http_api_key"
}

public struct SecretReference: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: SecretProvider
    public var purpose: String
    public var storage: String

    public init(id: String, provider: SecretProvider, purpose: String) {
        self.id = id
        self.provider = provider
        self.purpose = purpose
        self.storage = "keychain_or_server_environment"
    }
}

public struct ActionStep: Equatable, Identifiable, Sendable {
    public var id: String
    public var action: ActionKind
    public var parameters: [String: JSONValue]
    public var timeoutMs: Int
    public var onFailure: FailurePolicy
    public var confirmation: Confirmation

    public init(
        id: String = UUID().uuidString,
        action: ActionKind,
        parameters: [String: JSONValue] = [:],
        timeoutMs: Int = 10_000,
        onFailure: FailurePolicy = .stop,
        confirmation: Confirmation = .init()
    ) {
        self.id = id
        self.action = action
        self.parameters = parameters
        self.timeoutMs = timeoutMs
        self.onFailure = onFailure
        self.confirmation = confirmation
    }

    public var timeoutSeconds: Double { Double(timeoutMs) / 1_000 }
    public var confirmationRequired: Bool { confirmation.isRequired }

    public var plainEnglish: String {
        switch action {
        case .openApplication: return "Open \(parameters["applicationName"]?.stringValue ?? parameters["bundleIdentifier"]?.stringValue ?? "application")"
        case .openURL: return "Open \(parameters["url"]?.stringValue ?? "URL")"
        case .keyboardShortcut: return "Press \(parameters["key"]?.stringValue ?? "shortcut")"
        case .typeText: return "Type “\(parameters["text"]?.stringValue ?? "")”"
        case .wait: return "Wait \(Int(parameters["durationMs"]?.numberValue ?? 1_000)) ms"
        case .showNotification: return "Show notification"
        case .speakText: return "Speak “\(parameters["text"]?.stringValue ?? "")”"
        case .discordWebhook: return "Send configured Discord message"
        case .slackWebhook: return "Send configured Slack message"
        default: return action.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension ActionStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, action, timeoutMs, onFailure, confirmation
    }

    private struct ActionWire: Codable {
        var type: ActionKind
        var parameters: [String: JSONValue]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let wire = try container.decode(ActionWire.self, forKey: .action)
        action = wire.type
        parameters = wire.parameters
        timeoutMs = try container.decode(Int.self, forKey: .timeoutMs)
        onFailure = try container.decode(FailurePolicy.self, forKey: .onFailure)
        confirmation = try container.decode(Confirmation.self, forKey: .confirmation)
    }

    public func encode(to encoder: Encoder) throws {
        for key in parameters.keys {
            let normalized = key.lowercased()
            if normalized.contains("token") || normalized.contains("password") ||
                (normalized.contains("secret") && normalized != "secretref" && normalized != "secretrefs") {
                throw ModelValidationError.secretEmbedded(key)
            }
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ActionWire(type: action, parameters: parameters), forKey: .action)
        try container.encode(timeoutMs, forKey: .timeoutMs)
        try container.encode(onFailure, forKey: .onFailure)
        try container.encode(confirmation, forKey: .confirmation)
    }
}

public struct ActionPlan: Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var description: String
    public var steps: [ActionStep]
    public var timeoutMs: Int
    public var onFailure: FailurePolicy
    public var confirmation: Confirmation
    public var createdSource: PlanSource
    public var secretReferences: [SecretReference]
    /// Local review state. Deliberately excluded from portable JSON.
    public var approved: Bool

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        name: String,
        description: String,
        steps: [ActionStep],
        timeoutMs: Int = 60_000,
        onFailure: FailurePolicy = .stop,
        confirmation: Confirmation = .init(mode: .firstRun, reason: "Review before first run."),
        createdSource: PlanSource,
        secretReferences: [SecretReference] = [],
        approved: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.description = description
        self.steps = steps
        self.timeoutMs = timeoutMs
        self.onFailure = onFailure
        self.confirmation = confirmation
        self.createdSource = createdSource
        self.secretReferences = secretReferences
        self.approved = approved
    }

    public var timeoutSeconds: Double { Double(timeoutMs) / 1_000 }
    public var confirmationRequired: Bool { confirmation.isRequired }
}

extension ActionPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, description, steps, timeoutMs, onFailure
        case confirmation, createdSource, secretReferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        steps = try container.decode([ActionStep].self, forKey: .steps)
        timeoutMs = try container.decode(Int.self, forKey: .timeoutMs)
        onFailure = try container.decode(FailurePolicy.self, forKey: .onFailure)
        confirmation = try container.decode(Confirmation.self, forKey: .confirmation)
        createdSource = try container.decode(PlanSource.self, forKey: .createdSource)
        secretReferences = try container.decode([SecretReference].self, forKey: .secretReferences)
        approved = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(steps, forKey: .steps)
        try container.encode(timeoutMs, forKey: .timeoutMs)
        try container.encode(onFailure, forKey: .onFailure)
        try container.encode(confirmation, forKey: .confirmation)
        try container.encode(createdSource, forKey: .createdSource)
        try container.encode(secretReferences, forKey: .secretReferences)
    }
}

public enum ModelValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyName
    case emptyPlan
    case tooManySteps
    case invalidTimeout
    case missingParameter(action: ActionKind, name: String)
    case unsafeURL(String)
    case advancedActionDisabled(ActionKind)
    case unapprovedPlan
    case secretEmbedded(String)
    case duplicateGesture

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let value): return "Unsupported schemaVersion \(value)"
        case .emptyName: return "A name is required."
        case .emptyPlan: return "At least one action is required."
        case .tooManySteps: return "Plans may contain at most 50 steps."
        case .invalidTimeout: return "Timeout is outside the allowed range."
        case .missingParameter(let action, let name): return "\(action.rawValue) requires \(name)."
        case .unsafeURL(let value): return "Unsafe or non-public URL blocked: \(value)"
        case .advancedActionDisabled(let action): return "\(action.rawValue) requires Advanced Mode."
        case .unapprovedPlan: return "The plan must be reviewed and approved."
        case .secretEmbedded(let key): return "Secret-looking field \(key) must use a secret reference."
        case .duplicateGesture: return "A gesture may appear only once in a profile."
        }
    }
}

public struct ActionPlanValidator: Sendable {
    public var allowAdvancedActions: Bool
    public var requireApproval: Bool

    public init(allowAdvancedActions: Bool = false, requireApproval: Bool = true) {
        self.allowAdvancedActions = allowAdvancedActions
        self.requireApproval = requireApproval
    }

    public func validate(_ plan: ActionPlan) throws {
        guard plan.schemaVersion == 1 else {
            throw ModelValidationError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelValidationError.emptyName
        }
        guard !plan.steps.isEmpty else { throw ModelValidationError.emptyPlan }
        guard plan.steps.count <= 50 else { throw ModelValidationError.tooManySteps }
        guard (100...300_000).contains(plan.timeoutMs) else {
            throw ModelValidationError.invalidTimeout
        }
        if requireApproval && !plan.approved { throw ModelValidationError.unapprovedPlan }

        for step in plan.steps {
            guard (100...60_000).contains(step.timeoutMs) else {
                throw ModelValidationError.invalidTimeout
            }
            if step.action.isAdvanced && !allowAdvancedActions {
                throw ModelValidationError.advancedActionDisabled(step.action)
            }
            try validateParameters(step, secretReferences: plan.secretReferences)
        }
    }

    private func validateParameters(_ step: ActionStep, secretReferences: [SecretReference]) throws {
        func requireString(_ name: String) throws -> String {
            guard let value = step.parameters[name]?.stringValue,
                  !value.isEmpty else {
                throw ModelValidationError.missingParameter(action: step.action, name: name)
            }
            return value
        }

        func requireNumber(_ name: String) throws -> Double {
            guard let value = step.parameters[name]?.numberValue else {
                throw ModelValidationError.missingParameter(action: step.action, name: name)
            }
            return value
        }

        switch step.action {
        case .openApplication, .focusApplication:
            _ = try requireString("bundleIdentifier")
        case .openURL:
            let rawURL = try requireString("url")
            try validatePublicURL(rawURL)
            guard step.parameters["networkPolicy"]?.stringValue == "public_https_only" else {
                throw ModelValidationError.missingParameter(action: step.action, name: "networkPolicy")
            }
        case .openDeepLink:
            let scheme = try requireString("scheme")
            let rawURL = try requireString("url")
            let allowed = ["facetime", "macappstore", "mailto", "music", "shortcuts", "spotify"]
            guard allowed.contains(scheme),
                  URL(string: rawURL)?.scheme?.lowercased() == scheme else {
                throw ModelValidationError.unsafeURL(rawURL)
            }
        case .httpRequest:
            let rawURL = try requireString("url")
            try validatePublicURL(rawURL)
            guard step.parameters["networkPolicy"]?.stringValue == "public_https_only" else {
                throw ModelValidationError.missingParameter(action: step.action, name: "networkPolicy")
            }
        case .keyboardShortcut:
            _ = try requireString("key")
        case .typeText, .speakText, .setClipboard:
            _ = try requireString("text")
            if step.action == .typeText || step.action == .setClipboard {
                guard step.parameters["containsSensitiveData"]?.boolValue == false else {
                    throw ModelValidationError.missingParameter(action: step.action, name: "containsSensitiveData")
                }
            }
        case .wait:
            let duration = try requireNumber("durationMs")
            guard (0...30_000).contains(duration) else {
                throw ModelValidationError.missingParameter(action: step.action, name: "durationMs")
            }
        case .discordWebhook, .slackWebhook:
            _ = try requireString("message")
            guard let secretRef = step.parameters["secretRef"]?.stringValue,
                  secretReferences.contains(where: { $0.id == secretRef }) else {
                throw ModelValidationError.missingParameter(action: step.action, name: "secretRef")
            }
        case .runAppleShortcut:
            _ = try requireString("shortcutName")
        case .runAppleScriptTemplate:
            _ = try requireString("templateId")
            guard case .object = step.parameters["arguments"] else {
                throw ModelValidationError.missingParameter(action: step.action, name: "arguments")
            }
        case .clickScreenPoint:
            _ = try requireNumber("x")
            _ = try requireNumber("y")
            guard step.parameters["coordinateSpace"]?.stringValue == "normalized_active_display" else {
                throw ModelValidationError.missingParameter(action: step.action, name: "coordinateSpace")
            }
        case .scrollAmount:
            _ = try requireNumber("horizontal")
            _ = try requireNumber("vertical")
        case .zoomSteps:
            let steps = try requireNumber("steps")
            guard steps != 0, (-20...20).contains(steps) else {
                throw ModelValidationError.missingParameter(action: step.action, name: "steps")
            }
        default:
            break
        }

        for key in step.parameters.keys {
            let normalized = key.lowercased()
            if normalized.contains("token") || normalized.contains("password") ||
                (normalized.contains("secret") && normalized != "secretref") {
                throw ModelValidationError.secretEmbedded(key)
            }
        }
    }

    public func validatePublicURL(_ value: String, allowsDeepLink: Bool = false) throws {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased() else {
            throw ModelValidationError.unsafeURL(value)
        }
        if allowsDeepLink && !["http", "https", "file", "javascript"].contains(scheme) { return }
        guard scheme == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw ModelValidationError.unsafeURL(value)
        }
        let blockedHosts = ["localhost", "0.0.0.0", "127.0.0.1", "::1"]
        guard !blockedHosts.contains(host),
              !host.hasSuffix(".local"),
              !isBlockedLiteralIPAddress(host) else {
            throw ModelValidationError.unsafeURL(value)
        }
    }

    private func isBlockedLiteralIPAddress(_ host: String) -> Bool {
        if host.contains(":") {
            let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
            return value == "::" || value == "::1" ||
                value.hasPrefix("fc") || value.hasPrefix("fd") ||
                value.hasPrefix("fe8") || value.hasPrefix("fe9") ||
                value.hasPrefix("fea") || value.hasPrefix("feb") ||
                value.hasPrefix("ff") || value.hasPrefix("2001:db8")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        let a = parts[0], b = parts[1], c = parts[2]
        return a == 0 || a == 10 || a == 127 ||
            (a == 100 && (64...127).contains(b)) ||
            (a == 169 && b == 254) ||
            (a == 172 && (16...31).contains(b)) ||
            (a == 192 && b == 168) ||
            (a == 192 && b == 0 && c == 2) ||
            (a == 198 && b == 18 || a == 198 && b == 19) ||
            (a == 198 && b == 51 && c == 100) ||
            (a == 203 && b == 0 && c == 113) ||
            a >= 224
    }
}

public enum NativeActionCatalog {
    /// Actions the release executor can perform without arbitrary code or generic network transport.
    public static let executable: [ActionKind] = [
        .openApplication, .openURL, .keyboardShortcut, .typeText, .wait,
        .showNotification, .speakText, .playSound, .setClipboard,
        .runAppleShortcut, .runAppleScriptTemplate,
        .discordWebhook, .slackWebhook, .setVolume,
        .focusApplication, .clickScreenPoint, .scrollAmount, .zoomSteps
    ]
}

public enum ActivationBehavior: String, Codable, Sendable {
    case oneShot = "one_shot"
    case `repeat`
}

public struct GestureMapping: Codable, Equatable, Identifiable, Sendable {
    public var gesture: CommandGesture
    public var enabled: Bool
    public var holdDurationMs: Int
    public var cooldownMs: Int
    public var activation: ActivationBehavior
    public var repeatIntervalMs: Int?
    public var allowedBundleIdentifiers: [String]
    public var preferredMode: SignalMode?
    public var plan: ActionPlan

    public var id: String { gesture.rawValue }

    public init(
        gesture: CommandGesture,
        plan: ActionPlan,
        enabled: Bool = true,
        holdDurationMs: Int = 600,
        cooldownMs: Int = 900,
        activation: ActivationBehavior = .oneShot,
        repeatIntervalMs: Int? = nil,
        allowedBundleIdentifiers: [String] = [],
        preferredMode: SignalMode? = .command
    ) {
        self.gesture = gesture
        self.enabled = enabled
        self.holdDurationMs = holdDurationMs
        self.cooldownMs = cooldownMs
        self.activation = activation
        self.repeatIntervalMs = repeatIntervalMs
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.preferredMode = preferredMode
        self.plan = plan
    }
}

public enum HybridOneBehavior: String, Codable, Sendable {
    case pointer
    case command
}

public enum ShareVisibility: String, Codable, Sendable {
    case `private`
    case unlisted
}

public struct ShareMetadata: Codable, Equatable, Sendable {
    public var visibility: ShareVisibility
    public var shareCode: String?

    public init(visibility: ShareVisibility = .private, shareCode: String? = nil) {
        self.visibility = visibility
        self.shareCode = shareCode
    }
}

public struct SignalProfile: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var description: String
    public var preferredMode: SignalMode
    public var hybridOneBehavior: HybridOneBehavior
    public var mappings: [GestureMapping]
    public var share: ShareMetadata

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        preferredMode: SignalMode = .hybrid,
        hybridOneBehavior: HybridOneBehavior = .pointer,
        mappings: [GestureMapping] = [],
        share: ShareMetadata = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.description = description
        self.preferredMode = preferredMode
        self.hybridOneBehavior = hybridOneBehavior
        self.mappings = mappings
        self.share = share
    }
}

public struct ProfileValidator: Sendable {
    public init() {}

    public func validate(_ profile: SignalProfile) throws {
        guard profile.schemaVersion == 1 else {
            throw ModelValidationError.unsupportedSchemaVersion(profile.schemaVersion)
        }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelValidationError.emptyName
        }
        let uniqueGestures = Set(profile.mappings.map(\.gesture))
        guard uniqueGestures.count == profile.mappings.count else {
            throw ModelValidationError.duplicateGesture
        }
        for mapping in profile.mappings {
            guard (250...3_000).contains(mapping.holdDurationMs),
                  (0...10_000).contains(mapping.cooldownMs) else {
                throw ModelValidationError.invalidTimeout
            }
            var validator = ActionPlanValidator(requireApproval: false)
            validator.allowAdvancedActions = false
            try validator.validate(mapping.plan)
        }
    }
}
