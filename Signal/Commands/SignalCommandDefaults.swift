import Foundation

public enum SignalDefaultCommandCatalog {
    public static let rickrollURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    public static let gmailRecipient = "allenjxu07@gmail.com"
    public static let gmailComposeURL =
        "https://mail.google.com/mail/?view=cm&fs=1&to=allenjxu07%40gmail.com"
    public static let cursorAgentsURL = "https://cursor.com/agents"
    public static let newGoogleDocumentURL = "https://doc.new"
    public static let boltPrompt = "i want to build a website for my hand signal app"
    public static let anthropicXURL = "https://x.com/AnthropicAI?lang=en"

    public static let document = SignalCommandDocument(
        profile: SignalCommandProfile(
            id: "signal.defaults.v1",
            name: "Signal Defaults",
            commands: [
                fixedURL(
                    gesture: .one,
                    name: "Rickroll",
                    details: "Open the Rickroll video.",
                    url: rickrollURL
                ),
                fixedURL(
                    gesture: .two,
                    name: "New Gmail",
                    details: "Open a Gmail compose page with the recipient populated.",
                    url: gmailComposeURL
                ),
                fixedURL(
                    gesture: .three,
                    name: "Cursor Agents",
                    details: "Open Cursor Agents.",
                    url: cursorAgentsURL
                ),
                fixedURL(
                    gesture: .four,
                    name: "New Google Doc",
                    details: "Create a new Google document.",
                    url: newGoogleDocumentURL
                ),
                SignalCommandDefinition(
                    id: "signal.default.v1.thumbs-up",
                    gesture: .thumbsUp,
                    name: "Build with Bolt",
                    details: "Open Bolt and submit the reviewed Signal build prompt.",
                    plan: singleStepPlan(
                        gestureID: "thumbs-up",
                        action: .boltPrompt(.init(prompt: boltPrompt)),
                        timeoutMilliseconds: 20_000
                    )
                ),
                SignalCommandDefinition(
                    id: "signal.default.v1.thumbs-down",
                    gesture: .thumbsDown,
                    name: "Next Spotify Track",
                    details: "Advance Spotify Web to the next track.",
                    plan: singleStepPlan(
                        gestureID: "thumbs-down",
                        action: .spotifyNextTrack(.init()),
                        timeoutMilliseconds: 15_000
                    )
                ),
                fixedURL(
                    gesture: .cShape,
                    name: "Anthropic on X",
                    details: "Open Anthropic on X.",
                    url: anthropicXURL
                ),
                SignalCommandDefinition(
                    id: "signal.default.v1.fist",
                    gesture: .fist,
                    name: "Custom Command",
                    details: "Configure a safe HTTPS action for Fist.",
                    isConfigurable: true,
                    plan: nil
                )
            ]
        )
    )

    private static func fixedURL(
        gesture: SignalCommandGesture,
        name: String,
        details: String,
        url: String
    ) -> SignalCommandDefinition {
        let identifier = gesture.rawValue.replacingOccurrences(of: "_", with: "-")
        return SignalCommandDefinition(
            id: "signal.default.v1.\(identifier)",
            gesture: gesture,
            name: name,
            details: details,
            plan: singleStepPlan(
                gestureID: identifier,
                action: .openURL(.init(url: url)),
                timeoutMilliseconds: 15_000
            )
        )
    }

    private static func singleStepPlan(
        gestureID: String,
        action: SignalCommandAction,
        timeoutMilliseconds: Int
    ) -> SignalCommandPlan {
        SignalCommandPlan(
            id: "signal.default.v1.\(gestureID).plan",
            steps: [
                SignalCommandStep(
                    id: "signal.default.v1.\(gestureID).step-1",
                    action: action,
                    timeoutMilliseconds: timeoutMilliseconds
                )
            ],
            timeoutMilliseconds: min(timeoutMilliseconds + 5_000, 300_000)
        )
    }
}
