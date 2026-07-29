import Foundation

/// Concrete bridge between the closed command schema and the native/browser
/// adapters. No action can supply script source, selectors, shell text, or an
/// arbitrary browser automation destination.
public struct SignalNativeCommandPerformer:
    SignalCommandActionPerforming,
    Sendable
{
    private let urlPolicy: SignalCommandURLPolicy
    private let urlLauncher: any SignalHTTPSURLLaunching
    private let browserAutomation: any BrowserAutomationControlling

    public init(urlPolicy: SignalCommandURLPolicy = .init()) {
        let launcher = NSWorkspaceHTTPSURLLauncher(urlPolicy: urlPolicy)
        let browserLauncher = NSWorkspaceHTTPSURLLauncher.chromePreferred(
            urlPolicy: urlPolicy
        )
        self.urlPolicy = urlPolicy
        self.urlLauncher = launcher
        self.browserAutomation = BrowserAutomationController(
            urlPolicy: urlPolicy,
            urlLauncher: browserLauncher,
            clipboard: NSPasteboardSignalClipboardWriter(),
            chrome: ChromeAutomationAdapter()
        )
    }

    public init(
        urlPolicy: SignalCommandURLPolicy = .init(),
        urlLauncher: any SignalHTTPSURLLaunching,
        browserAutomation: any BrowserAutomationControlling
    ) {
        self.urlPolicy = urlPolicy
        self.urlLauncher = urlLauncher
        self.browserAutomation = browserAutomation
    }

    public func perform(
        _ action: SignalCommandAction,
        context: SignalCommandExecutionContext
    ) async throws -> String {
        try context.checkCancellation()
        switch action {
        case .openURL(let payload):
            let url: URL
            do {
                url = try urlPolicy.validate(payload.url)
            } catch {
                throw SignalNativeCommandError.unsafeDestination
            }

            try context.checkCancellation()
            try await urlLauncher.openHTTPSURL(url)
            return "Opened the approved HTTPS destination."

        case .boltPrompt(let payload):
            guard payload.prompt == SignalDefaultCommandCatalog.boltPrompt else {
                throw SignalNativeCommandError.unsupportedBoltPrompt
            }

            try context.checkCancellation()
            return try await browserAutomation.submitReviewedBoltPrompt(
                SignalDefaultCommandCatalog.boltPrompt,
                context: context
            )

        case .spotifyNextTrack:
            try context.checkCancellation()
            return try await browserAutomation.skipSpotifyWebTrack(
                context: context
            )
        }
    }
}
