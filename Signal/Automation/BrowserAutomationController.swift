import Foundation

public protocol BrowserAutomationControlling: Sendable {
    func submitReviewedBoltPrompt(
        _ prompt: String,
        context: SignalCommandExecutionContext
    ) async throws -> String

    func skipSpotifyWebTrack(
        context: SignalCommandExecutionContext
    ) async throws -> String
}

/// Serializes the two reviewed browser automations. It has no generic script,
/// selector, host, or media-control entry point.
public actor BrowserAutomationController: BrowserAutomationControlling {
    public static let boltURLString = "https://bolt.new/"
    public static let spotifyWebURLString = "https://open.spotify.com/"

    private let urlPolicy: SignalCommandURLPolicy
    private let urlLauncher: any SignalHTTPSURLLaunching
    private let clipboard: any SignalClipboardWriting
    private let chrome: any ChromeAutomationAdapting

    public init(
        urlPolicy: SignalCommandURLPolicy = .init(),
        urlLauncher: any SignalHTTPSURLLaunching,
        clipboard: any SignalClipboardWriting,
        chrome: any ChromeAutomationAdapting
    ) {
        self.urlPolicy = urlPolicy
        self.urlLauncher = urlLauncher
        self.clipboard = clipboard
        self.chrome = chrome
    }

    public init(urlPolicy: SignalCommandURLPolicy = .init()) {
        let launcher = NSWorkspaceHTTPSURLLauncher.chromePreferred(
            urlPolicy: urlPolicy
        )
        self.urlPolicy = urlPolicy
        self.urlLauncher = launcher
        self.clipboard = NSPasteboardSignalClipboardWriter()
        self.chrome = ChromeAutomationAdapter()
    }

    public func submitReviewedBoltPrompt(
        _ prompt: String,
        context: SignalCommandExecutionContext
    ) async throws -> String {
        guard prompt == SignalDefaultCommandCatalog.boltPrompt else {
            throw SignalNativeCommandError.unsupportedBoltPrompt
        }
        let boltURL = try approvedURL(
            Self.boltURLString,
            exactHost: "bolt.new"
        )

        try context.checkCancellation()
        try await urlLauncher.openHTTPSURL(boltURL)

        do {
            try context.checkCancellation()
            let outcome = try await chrome.submitReviewedBoltPrompt(
                context: context
            )
            guard outcome == .boltPromptSubmitted else {
                throw ChromeAutomationError.unexpectedResult
            }
            return "Submitted the reviewed Signal prompt in Bolt."
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChromeAutomationError {
            try context.checkCancellation()
            try await clipboard.writeString(
                SignalDefaultCommandCatalog.boltPrompt
            )
            try context.checkCancellation()
            throw SignalNativeCommandError.boltFallbackReady(error)
        } catch {
            try context.checkCancellation()
            try await clipboard.writeString(
                SignalDefaultCommandCatalog.boltPrompt
            )
            try context.checkCancellation()
            throw SignalNativeCommandError.boltFallbackReady(
                .scriptExecutionFailed
            )
        }
    }

    public func skipSpotifyWebTrack(
        context: SignalCommandExecutionContext
    ) async throws -> String {
        let spotifyURL = try approvedURL(
            Self.spotifyWebURLString,
            exactHost: "open.spotify.com"
        )

        try context.checkCancellation()
        try await urlLauncher.openHTTPSURL(spotifyURL)

        try context.checkCancellation()
        let outcome = try await chrome.skipSpotifyWebTrack(context: context)
        guard outcome == .spotifyTrackSkipped else {
            throw ChromeAutomationError.unexpectedResult
        }
        return "Skipped one track in Spotify Web."
    }

    private func approvedURL(
        _ value: String,
        exactHost: String
    ) throws -> URL {
        do {
            return try urlPolicy.validate(value, exactHost: exactHost)
        } catch {
            throw SignalNativeCommandError.unsafeDestination
        }
    }
}
