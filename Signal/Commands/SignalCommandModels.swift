import Foundation

/// The complete command-facing gesture set. `five` is intentionally absent.
public enum SignalCommandGesture: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case one
    case two
    case three
    case four
    case thumbsUp = "thumbs_up"
    case thumbsDown = "thumbs_down"
    case cShape = "c_shape"
    case fist
}

public enum SignalCommandFailurePolicy: String, Codable, Equatable, Sendable {
    case stop
    case `continue`
}

public struct SignalOpenURLAction: Codable, Equatable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

public struct SignalBoltPromptAction: Codable, Equatable, Sendable {
    public var prompt: String

    public init(prompt: String) {
        self.prompt = prompt
    }
}

public struct SignalSpotifyNextTrackAction: Codable, Equatable, Sendable {
    public init() {}
}

/// Closed action vocabulary. There is no generic script, shell, HTTP, or JavaScript action.
public enum SignalCommandAction: Equatable, Sendable {
    case openURL(SignalOpenURLAction)
    case boltPrompt(SignalBoltPromptAction)
    case spotifyNextTrack(SignalSpotifyNextTrackAction)

    public enum Kind: String, Codable, Equatable, Sendable {
        case openURL = "open_url"
        case boltPrompt = "bolt_submit_prompt"
        case spotifyNextTrack = "spotify_next_track"
    }

    public var kind: Kind {
        switch self {
        case .openURL: .openURL
        case .boltPrompt: .boltPrompt
        case .spotifyNextTrack: .spotifyNextTrack
        }
    }
}

extension SignalCommandAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .openURL:
            self = .openURL(
                try container.decode(SignalOpenURLAction.self, forKey: .parameters)
            )
        case .boltPrompt:
            self = .boltPrompt(
                try container.decode(SignalBoltPromptAction.self, forKey: .parameters)
            )
        case .spotifyNextTrack:
            self = .spotifyNextTrack(
                try container.decode(SignalSpotifyNextTrackAction.self, forKey: .parameters)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .openURL(let payload):
            try container.encode(payload, forKey: .parameters)
        case .boltPrompt(let payload):
            try container.encode(payload, forKey: .parameters)
        case .spotifyNextTrack(let payload):
            try container.encode(payload, forKey: .parameters)
        }
    }
}

public struct SignalCommandStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var action: SignalCommandAction
    public var timeoutMilliseconds: Int
    public var failurePolicy: SignalCommandFailurePolicy

    public init(
        id: String,
        action: SignalCommandAction,
        timeoutMilliseconds: Int = 10_000,
        failurePolicy: SignalCommandFailurePolicy = .stop
    ) {
        self.id = id
        self.action = action
        self.timeoutMilliseconds = timeoutMilliseconds
        self.failurePolicy = failurePolicy
    }
}

public struct SignalCommandPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var steps: [SignalCommandStep]
    public var timeoutMilliseconds: Int

    public init(
        id: String,
        steps: [SignalCommandStep],
        timeoutMilliseconds: Int = 30_000
    ) {
        self.id = id
        self.steps = steps
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}

public struct SignalCommandDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var gesture: SignalCommandGesture
    public var name: String
    public var details: String
    public var isConfigurable: Bool
    public var plan: SignalCommandPlan?

    public init(
        id: String,
        gesture: SignalCommandGesture,
        name: String,
        details: String,
        isConfigurable: Bool = false,
        plan: SignalCommandPlan?
    ) {
        self.id = id
        self.gesture = gesture
        self.name = name
        self.details = details
        self.isConfigurable = isConfigurable
        self.plan = plan
    }
}

public struct SignalCommandProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var commands: [SignalCommandDefinition]

    public init(id: String, name: String, commands: [SignalCommandDefinition]) {
        self.id = id
        self.name = name
        self.commands = commands
    }

    public subscript(gesture: SignalCommandGesture) -> SignalCommandDefinition? {
        commands.first { $0.gesture == gesture }
    }
}

public struct SignalCommandDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let currentCatalogVersion = 1

    public var schemaVersion: Int
    public var catalogVersion: Int
    public var profile: SignalCommandProfile

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        catalogVersion: Int = Self.currentCatalogVersion,
        profile: SignalCommandProfile
    ) {
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.profile = profile
    }
}

public enum SignalCommandValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedCatalogVersion(Int)
    case invalidField(path: String, reason: String)
    case duplicateIdentifier(String)
    case duplicateGesture(SignalCommandGesture)
    case missingGesture(SignalCommandGesture)
    case unexpectedJSONField(path: String, field: String)
    case unsafeURL(String)
    case malformedJSON

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported command schema version \(version)."
        case .unsupportedCatalogVersion(let version):
            "Unsupported command catalog version \(version)."
        case .invalidField(let path, let reason):
            "\(path) is invalid: \(reason)"
        case .duplicateIdentifier(let identifier):
            "Duplicate identifier: \(identifier)"
        case .duplicateGesture(let gesture):
            "Duplicate gesture: \(gesture.rawValue)"
        case .missingGesture(let gesture):
            "Missing gesture: \(gesture.rawValue)"
        case .unexpectedJSONField(let path, let field):
            "Unexpected field \(field) at \(path)."
        case .unsafeURL(let value):
            "Unsafe URL: \(value)"
        case .malformedJSON:
            "The command document is not valid JSON."
        }
    }
}
