import Foundation

public struct PlannerConfiguration: Codable, Equatable, Sendable {
    public static let productionEndpoint = URL(
        string: "https://signal-hand-control.allenxtech.chatgpt.site/api/v1/plan"
    )!

    public var endpoint: URL
    public var timeoutSeconds: Double

    public init(
        endpoint: URL = Self.productionEndpoint,
        timeoutSeconds: Double = 12
    ) {
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
    }

    public func validate() throws {
        try ActionPlanValidator(requireApproval: false).validatePublicURL(endpoint.absoluteString)
    }
}

public struct PlannerRequest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestId: String
    public var request: String
    public var targetGesture: CommandGesture?
    public var actionCatalog: [ActionKind]

    public init(
        request: String,
        targetGesture: CommandGesture? = nil,
        actionCatalog: [ActionKind] = NativeActionCatalog.executable
    ) {
        schemaVersion = 1
        requestId = "native-\(UUID().uuidString.prefix(24))"
        self.request = request
        self.targetGesture = targetGesture
        self.actionCatalog = Array(actionCatalog.prefix(32))
    }
}

public enum PlannerStatus: String, Codable, Sendable {
    case planned
    case needsClarification = "needs_clarification"
}

public struct PlannerResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestId: String
    public var status: PlannerStatus
    public var plan: ActionPlan?
    public var warnings: [String]?
    public var usedDeterministicFallback: Bool?
    public var question: String?
    public var missingFields: [String]?

    public init(
        schemaVersion: Int = 1,
        requestId: String,
        status: PlannerStatus,
        plan: ActionPlan? = nil,
        warnings: [String]? = nil,
        usedDeterministicFallback: Bool? = nil,
        question: String? = nil,
        missingFields: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.status = status
        self.plan = plan
        self.warnings = warnings
        self.usedDeterministicFallback = usedDeterministicFallback
        self.question = question
        self.missingFields = missingFields
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw ModelValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        switch status {
        case .planned:
            guard let plan, warnings != nil, usedDeterministicFallback != nil else {
                throw ModelValidationError.emptyPlan
            }
            try ActionPlanValidator(requireApproval: false).validate(plan)
        case .needsClarification:
            guard let question, !question.isEmpty,
                  let missingFields, !missingFields.isEmpty,
                  plan == nil else {
                throw ModelValidationError.emptyPlan
            }
        }
    }
}

public enum PlannerSource: Equatable, Sendable {
    case remote
    case seededOffline(reason: String)
}

public struct PlannerResult: Equatable, Sendable {
    public var response: PlannerResponse
    public var source: PlannerSource
    public var interpretedGesture: CommandGesture?
}

public actor PlannerClient {
    private var configuration: PlannerConfiguration
    private let session: URLSession

    public init(configuration: PlannerConfiguration = .init(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func update(configuration: PlannerConfiguration) throws {
        try configuration.validate()
        self.configuration = configuration
    }

    public func plan(_ prompt: String, targetGesture: CommandGesture? = nil) async -> PlannerResult {
        do {
            try configuration.validate()
            let plannerRequest = PlannerRequest(request: prompt, targetGesture: targetGesture)
            var request = URLRequest(url: configuration.endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = configuration.timeoutSeconds
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(plannerRequest)
            let (data, response) = try await session.data(for: request)
            guard data.count <= 1_048_576,
                  let http = response as? HTTPURLResponse,
                  http.url == configuration.endpoint,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(PlannerResponse.self, from: data)
            try decoded.validate()
            return PlannerResult(
                response: decoded,
                source: .remote,
                interpretedGesture: targetGesture ?? Self.inferGesture(prompt)
            )
        } catch {
            return offlinePlan(for: prompt, targetGesture: targetGesture, reason: error.localizedDescription)
        }
    }

    public nonisolated func offlinePlan(
        for prompt: String,
        targetGesture: CommandGesture? = nil,
        reason: String = "Offline"
    ) -> PlannerResult {
        let inferred = targetGesture ?? Self.inferGesture(prompt)
        let response: PlannerResponse
        if Self.isFocusPhrase(prompt) {
            response = PlannerResponse(
                requestId: "offline-focus",
                status: .planned,
                plan: SeededContent.focusPlan(),
                warnings: ["Using Signal’s local validated focus fallback."],
                usedDeterministicFallback: true
            )
        } else {
            response = PlannerResponse(
                requestId: "offline-clarify",
                status: .needsClarification,
                question: "Which supported app, URL, or action should this gesture run?",
                missingFields: ["action"]
            )
        }
        return PlannerResult(
            response: response,
            source: .seededOffline(reason: reason),
            interpretedGesture: inferred
        )
    }

    private nonisolated static func inferGesture(_ prompt: String) -> CommandGesture? {
        let lower = prompt.lowercased()
        if lower.contains("thumb") && lower.contains("up") { return .thumbsUp }
        if lower.contains("c shape") || lower.contains("c-shape") { return .cShape }
        return nil
    }

    private nonisolated static func isFocusPhrase(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return lower.contains("focus") || lower.contains("spotify") || lower.contains("demo complete")
    }
}
