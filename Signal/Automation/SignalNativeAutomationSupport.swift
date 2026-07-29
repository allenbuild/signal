import AppKit
import Foundation

public enum SignalNativeCommandError: Error, Equatable, LocalizedError, Sendable {
    case unsafeDestination
    case unableToOpenDestination
    case clipboardUnavailable
    case unsupportedBoltPrompt
    case boltFallbackReady(ChromeAutomationError)

    public var isRecoverable: Bool {
        true
    }

    public var errorDescription: String? {
        switch self {
        case .unsafeDestination:
            "Signal refused to open an unsafe destination."
        case .unableToOpenDestination:
            "Signal could not open the HTTPS destination."
        case .clipboardUnavailable:
            "Signal could not place the reviewed prompt on the clipboard."
        case .unsupportedBoltPrompt:
            "Signal refused a Bolt prompt that is not the reviewed built-in prompt."
        case .boltFallbackReady(let cause):
            """
            Bolt is open and the reviewed prompt is on the clipboard. \
            Paste and submit it manually. \(cause.localizedDescription)
            """
        }
    }
}

public protocol SignalHTTPSURLLaunching: Sendable {
    func openHTTPSURL(_ url: URL) async throws
}

public protocol SignalClipboardWriting: Sendable {
    func writeString(_ value: String) async throws
}

protocol SignalWorkspaceApplicationOpening: Sendable {
    func installedApplicationURL(bundleIdentifier: String) async -> URL?

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL?
    ) async throws -> Bool
}

struct SystemSignalWorkspaceApplicationOpener:
    SignalWorkspaceApplicationOpening,
    Sendable
{
    func installedApplicationURL(bundleIdentifier: String) async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        }
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL?
    ) async throws -> Bool {
        try Task.checkCancellation()
        return try await Self.openOnMainActor(
            url,
            withApplicationAt: applicationURL
        )
    }

    @MainActor
    private static func openOnMainActor(
        _ url: URL,
        withApplicationAt applicationURL: URL?
    ) async throws -> Bool {
        if let applicationURL {
            try Task.checkCancellation()
            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: .init()
                ) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
        }

        try Task.checkCancellation()
        return NSWorkspace.shared.open(url)
    }
}

/// Opens only policy-approved HTTPS destinations in the user's default browser.
/// A separate internal construction is used by the two Chrome-first, fixed-site
/// browser automations.
public struct NSWorkspaceHTTPSURLLauncher: SignalHTTPSURLLaunching, Sendable {
    public static let chromeBundleIdentifier = "com.google.Chrome"

    private let urlPolicy: SignalCommandURLPolicy
    private let workspace: any SignalWorkspaceApplicationOpening
    private let preferredBrowserBundleIdentifier: String?

    public init(urlPolicy: SignalCommandURLPolicy = .init()) {
        self.urlPolicy = urlPolicy
        self.workspace = SystemSignalWorkspaceApplicationOpener()
        self.preferredBrowserBundleIdentifier = nil
    }

    init(
        urlPolicy: SignalCommandURLPolicy = .init(),
        workspace: any SignalWorkspaceApplicationOpening,
        preferredBrowserBundleIdentifier: String?
    ) {
        self.urlPolicy = urlPolicy
        self.workspace = workspace
        self.preferredBrowserBundleIdentifier = preferredBrowserBundleIdentifier
    }

    static func chromePreferred(
        urlPolicy: SignalCommandURLPolicy = .init()
    ) -> Self {
        Self(
            urlPolicy: urlPolicy,
            workspace: SystemSignalWorkspaceApplicationOpener(),
            preferredBrowserBundleIdentifier: Self.chromeBundleIdentifier
        )
    }

    public func openHTTPSURL(_ url: URL) async throws {
        let approvedURL: URL
        do {
            approvedURL = try urlPolicy.validate(url.absoluteString)
        } catch {
            throw SignalNativeCommandError.unsafeDestination
        }

        if let preferredBrowserBundleIdentifier,
           let preferredApplication = await workspace.installedApplicationURL(
               bundleIdentifier: preferredBrowserBundleIdentifier
           ) {
            try Task.checkCancellation()
            let preferredOpened = try await workspace.open(
                approvedURL,
                withApplicationAt: preferredApplication
            )
            try Task.checkCancellation()
            guard preferredOpened else {
                throw SignalNativeCommandError.unableToOpenDestination
            }
            return
        }

        try Task.checkCancellation()
        let defaultOpened = try await workspace.open(
            approvedURL,
            withApplicationAt: nil
        )
        try Task.checkCancellation()
        guard defaultOpened else {
            throw SignalNativeCommandError.unableToOpenDestination
        }
    }
}

public struct NSPasteboardSignalClipboardWriter:
    SignalClipboardWriting,
    Sendable
{
    public init() {}

    public func writeString(_ value: String) async throws {
        try Task.checkCancellation()
        try await Self.writeOnMainActor(value)
    }

    @MainActor
    private static func writeOnMainActor(_ value: String) throws {
        try Task.checkCancellation()
        NSPasteboard.general.clearContents()

        try Task.checkCancellation()
        guard NSPasteboard.general.setString(value, forType: .string) else {
            throw SignalNativeCommandError.clipboardUnavailable
        }
    }
}
