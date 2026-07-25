import Foundation

public actor LocalProfileStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Signal", isDirectory: true)
        self.directory = base.appendingPathComponent("Profiles", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func save(_ profile: SignalProfile) throws {
        try ProfileValidator().validate(profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(profile).write(to: fileURL(for: profile.id), options: .atomic)
    }

    public func load(id: String) throws -> SignalProfile {
        let profile = try decoder.decode(SignalProfile.self, from: Data(contentsOf: fileURL(for: id)))
        try ProfileValidator().validate(profile)
        return profile
    }

    public func list() throws -> [SignalProfile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let profile = try? decoder.decode(SignalProfile.self, from: data),
                      (try? ProfileValidator().validate(profile)) != nil else { return nil }
                return profile
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func delete(id: String) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func export(_ profile: SignalProfile, to destination: URL) throws {
        try ProfileValidator().validate(profile)
        try encoder.encode(profile).write(to: destination, options: .atomic)
    }

    public func importProfile(from source: URL) throws -> SignalProfile {
        let profile = try decoder.decode(SignalProfile.self, from: Data(contentsOf: source))
        try ProfileValidator().validate(profile)
        return profile
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("json")
    }
}

public enum SeededContent {
    public static func onePlan(approved: Bool = false) -> ActionPlan {
        ActionPlan(
            id: "signal.seed.focus-url",
            name: "Open focus playlist",
            description: "Open a public Spotify focus playlist URL.",
            steps: [
                ActionStep(
                    id: "open-focus-url",
                    action: .openURL,
                    parameters: [
                        "url": .string("https://open.spotify.com/genre/0JQ5DAqbMKFAXlCG6QvYQ4"),
                        "networkPolicy": .string("public_https_only")
                    ],
                    confirmation: .init(mode: .firstRun, reason: "Opens a public URL in the default browser.")
                )
            ],
            timeoutMs: 15_000,
            confirmation: .init(mode: .firstRun, reason: "Review the destination before first run."),
            createdSource: .visual,
            approved: approved
        )
    }

    public static func focusPlan(approved: Bool = false) -> ActionPlan {
        let secret = SecretReference(
            id: "demo-discord-webhook",
            provider: .discord,
            purpose: "Optional hero-demo completion receipt"
        )
        return ActionPlan(
            id: "signal.seed.focus-mode",
            name: "Focus Mode",
            description: "Open Spotify, speak Focus mode, and send a configured Discord receipt.",
            steps: [
                ActionStep(
                    id: "open-focus-playlist",
                    action: .openURL,
                    parameters: [
                        "url": .string("https://open.spotify.com/genre/0JQ5DAqbMKFAXlCG6QvYQ4"),
                        "networkPolicy": .string("public_https_only")
                    ],
                    onFailure: .continue,
                    confirmation: .init(mode: .firstRun, reason: "Opens a public URL.")
                ),
                ActionStep(
                    id: "speak-focus-mode",
                    action: .speakText,
                    parameters: ["text": .string("Focus mode")],
                    onFailure: .continue
                ),
                ActionStep(
                    id: "send-demo-receipt",
                    action: .discordWebhook,
                    parameters: [
                        "secretRef": .string(secret.id),
                        "message": .string("Demo complete"),
                        "fallback": .string("local_receipt")
                    ],
                    onFailure: .continue,
                    confirmation: .init(mode: .everyRun, reason: "Sends the displayed message when configured.")
                )
            ],
            timeoutMs: 35_000,
            onFailure: .continue,
            confirmation: .init(mode: .firstRun, reason: "Review all external effects before first run."),
            createdSource: .naturalLanguage,
            secretReferences: [secret],
            approved: approved
        )
    }

    public static func cShapePlan(approved: Bool = false) -> ActionPlan {
        ActionPlan(
            id: "signal.seed.demo-replay",
            name: "Replay recorded note",
            description: "Open TextEdit, create a document, and type a short phrase.",
            steps: [
                ActionStep(
                    id: "open-textedit",
                    action: .openApplication,
                    parameters: [
                        "bundleIdentifier": .string("com.apple.TextEdit"),
                        "applicationName": .string("TextEdit")
                    ],
                    confirmation: .init(mode: .firstRun, reason: "Opens a local application.")
                ),
                ActionStep(
                    id: "new-document",
                    action: .keyboardShortcut,
                    parameters: ["key": .string("n"), "modifiers": .array([.string("command")])],
                    timeoutMs: 5_000,
                    confirmation: .init(mode: .firstRun, reason: "Sends Command-N.")
                ),
                ActionStep(
                    id: "type-demo-text",
                    action: .typeText,
                    parameters: [
                        "text": .string("Signal replayed this workflow with a hand gesture."),
                        "containsSensitiveData": .bool(false)
                    ],
                    confirmation: .init(mode: .firstRun, reason: "Types the displayed non-sensitive text.")
                )
            ],
            timeoutMs: 30_000,
            confirmation: .init(mode: .firstRun, reason: "Review keyboard and text-entry effects."),
            createdSource: .demoRecording,
            approved: approved
        )
    }

    public static func demoProfile(approved: Bool = true) -> SignalProfile {
        SignalProfile(
            id: "signal.seeded.hero",
            name: "Signal Hero Demo",
            description: "Offline-safe mappings for the hero flows.",
            preferredMode: .hybrid,
            mappings: [
                GestureMapping(gesture: .one, plan: onePlan(approved: approved), preferredMode: .command),
                GestureMapping(gesture: .thumbsUp, plan: focusPlan(approved: approved), preferredMode: .command),
                GestureMapping(
                    gesture: .cShape,
                    plan: cShapePlan(approved: approved),
                    holdDurationMs: 650,
                    cooldownMs: 1_000,
                    preferredMode: .command
                )
            ],
            share: .init(visibility: .unlisted, shareCode: "SIG1-SGNL2626")
        )
    }
}
