import ApplicationServices
import AppKit
import Foundation

public enum ChromeAutomationError: Error, Equatable, LocalizedError, Sendable {
    case chromeUnavailable
    case automationPermissionRequired
    case javaScriptFromAppleEventsDisabled
    case boltTabUnavailable
    case boltFieldUnavailable
    case boltSubmitUnavailable
    case spotifyTabUnavailable
    case spotifyNextControlUnavailable
    case spotifyTrackIdentityUnavailable
    case spotifySkipUnconfirmed
    case scriptCompilationFailed
    case scriptExecutionFailed
    case unexpectedResult

    public var isRecoverable: Bool {
        true
    }

    public var errorDescription: String? {
        switch self {
        case .chromeUnavailable:
            "Google Chrome is not installed or is not running."
        case .automationPermissionRequired:
            "Chrome automation permission is required in System Settings."
        case .javaScriptFromAppleEventsDisabled:
            """
            Chrome's “Allow JavaScript from Apple Events” setting is required \
            for this reviewed browser action.
            """
        case .boltTabUnavailable:
            "A verified bolt.new tab was not available."
        case .boltFieldUnavailable:
            "A single visible Bolt prompt field could not be verified."
        case .boltSubmitUnavailable:
            "The verified Bolt prompt field could not accept Return."
        case .spotifyTabUnavailable:
            "A verified open.spotify.com tab was not available."
        case .spotifyNextControlUnavailable:
            "Spotify Web's next-track control could not be verified."
        case .spotifyTrackIdentityUnavailable:
            "Start playback, then repeat Thumbs Down."
        case .spotifySkipUnconfirmed:
            "Spotify Web did not confirm the skipped track is playing."
        case .scriptCompilationFailed:
            "Signal's built-in Chrome automation could not be compiled."
        case .scriptExecutionFailed:
            "Signal's built-in Chrome automation could not be completed."
        case .unexpectedResult:
            "Chrome returned an unexpected automation result."
        }
    }
}

public enum ChromeAutomationOutcome: Equatable, Sendable {
    case boltPromptSubmitted
    case spotifyTrackSkipped
}

public protocol ChromeAutomationAdapting: Sendable {
    func submitReviewedBoltPrompt(
        context: SignalCommandExecutionContext
    ) async throws -> ChromeAutomationOutcome

    func skipSpotifyWebTrack(
        context: SignalCommandExecutionContext
    ) async throws -> ChromeAutomationOutcome
}

enum ChromeAutomationFixedProgram: Equatable, Sendable {
    case boltReviewedPrompt
    case spotifyNextTrack
    case spotifyVerifyNextTrack
    case spotifyConfirmPlayback

    var source: String {
        switch self {
        case .boltReviewedPrompt:
            Self.makeChromeProgram(
                exactHost: "bolt.new",
                tabURLPrefix: "https://bolt.new/",
                missingTabResult: "bolt_tab_unavailable",
                javaScript: Self.boltJavaScript
            )
        case .spotifyNextTrack:
            Self.makeChromeProgram(
                exactHost: "open.spotify.com",
                tabURLPrefix: "https://open.spotify.com/",
                missingTabResult: "spotify_tab_unavailable",
                javaScript: Self.spotifyJavaScript
            )
        case .spotifyVerifyNextTrack:
            Self.makeChromeProgram(
                exactHost: "open.spotify.com",
                tabURLPrefix: "https://open.spotify.com/",
                missingTabResult: "spotify_tab_unavailable",
                javaScript: Self.spotifyVerificationJavaScript
            )
        case .spotifyConfirmPlayback:
            Self.makeChromeProgram(
                exactHost: "open.spotify.com",
                tabURLPrefix: "https://open.spotify.com/",
                missingTabResult: "spotify_tab_unavailable",
                javaScript: Self.spotifyPlaybackConfirmationJavaScript
            )
        }
    }

    private static let boltJavaScript: String = {
        let promptBase64 = Data(
            SignalDefaultCommandCatalog.boltPrompt.utf8
        ).base64EncodedString()
        return """
        (() => {
          if (location.protocol !== 'https:' || location.hostname !== 'bolt.new') {
            return 'wrong_origin';
          }
          try {
            const isVisible = (element) => {
              const rect = element.getBoundingClientRect();
              const style = getComputedStyle(element);
              return rect.width > 0 && rect.height > 0 &&
                style.visibility !== 'hidden' && style.display !== 'none' &&
                element.getAttribute('aria-hidden') !== 'true' &&
                !element.disabled;
            };
            const fields = Array.from(document.querySelectorAll(
              `textarea[data-testid='chat-input'],
               textarea[aria-label='Prompt'],
               textarea[placeholder*='message' i],
               textarea[placeholder*='build' i]`
            )).filter(isVisible);
            if (fields.length !== 1) {
              return 'bolt_field_unavailable';
            }
            const field = fields[0];
            const form = field.closest('form');
            if (!form) {
              return 'bolt_submit_unavailable';
            }
            const setter = Object.getOwnPropertyDescriptor(
              HTMLTextAreaElement.prototype,
              'value'
            )?.set;
            if (!setter) {
              return 'bolt_field_unavailable';
            }
            const prompt = new TextDecoder().decode(
              Uint8Array.from(atob('\(promptBase64)'), (value) => value.charCodeAt(0))
            );
            field.focus();
            setter.call(field, prompt);
            field.dispatchEvent(new InputEvent('input', {
              bubbles: true,
              inputType: 'insertText',
              data: prompt
            }));
            if (field.value !== prompt || document.activeElement !== field) {
              return 'bolt_field_unavailable';
            }
            const enterWasHandled = !field.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Enter',
              code: 'Enter',
              keyCode: 13,
              which: 13,
              bubbles: true,
              cancelable: true,
              composed: true
            }));
            if (!enterWasHandled && field.value === prompt) {
              return 'bolt_submit_unavailable';
            }
            return 'bolt_submitted';
          } catch (_) {
            return 'bolt_field_unavailable';
          }
        })()
        """
    }()

    private static let spotifyJavaScript = """
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'open.spotify.com') {
        return 'wrong_origin';
      }
      try {
        const isVisible = (element) => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 0 && rect.height > 0 &&
            style.visibility !== 'hidden' && style.display !== 'none' &&
            element.getAttribute('aria-hidden') !== 'true' &&
            !element.disabled;
        };
        const controls = Array.from(document.querySelectorAll(
          `button[data-testid='control-button-skip-forward']`
        )).filter(isVisible);
        if (controls.length !== 1) {
          return 'spotify_next_control_unavailable';
        }
        const trackLinks = Array.from(document.querySelectorAll(
          `[data-testid='now-playing-widget']
           a[data-testid='context-item-link'][href*='/track/']`
        )).filter(isVisible);
        if (trackLinks.length !== 1) {
          return 'spotify_track_identity_unavailable';
        }
        delete document.documentElement.dataset.signalSpotifyTrackAfter;
        delete document.documentElement.dataset.signalSpotifyPlayActivated;
        document.documentElement.dataset.signalSpotifyTrackBefore =
          trackLinks[0].href;
        controls[0].click();
        return 'spotify_click_dispatched';
      } catch (_) {
        return 'spotify_next_control_unavailable';
      }
    })()
    """

    private static let spotifyVerificationJavaScript = """
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'open.spotify.com') {
        return 'wrong_origin';
      }
      try {
        const isVisible = (element) => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 0 && rect.height > 0 &&
            style.visibility !== 'hidden' && style.display !== 'none' &&
            element.getAttribute('aria-hidden') !== 'true' &&
            !element.disabled;
        };
        const before =
          document.documentElement.dataset.signalSpotifyTrackBefore;
        const trackLinks = Array.from(document.querySelectorAll(
          `[data-testid='now-playing-widget']
           a[data-testid='context-item-link'][href*='/track/']`
        )).filter(isVisible);
        if (!before || trackLinks.length !== 1) {
          return 'spotify_track_identity_unavailable';
        }
        const playbackControls = Array.from(document.querySelectorAll(
          `button[data-testid='control-button-playpause']`
        )).filter(isVisible);
        if (playbackControls.length !== 1 || trackLinks[0].href === before) {
          return 'spotify_skip_unconfirmed';
        }
        const playbackLabel = (
          playbackControls[0].getAttribute('aria-label') ||
          playbackControls[0].getAttribute('title') ||
          ''
        ).trim().toLowerCase();
        if (playbackLabel === 'pause') {
          delete document.documentElement.dataset.signalSpotifyTrackBefore;
          return 'spotify_skipped';
        }
        if (playbackLabel !== 'play') {
          return 'spotify_skip_unconfirmed';
        }
        document.documentElement.dataset.signalSpotifyTrackAfter =
          trackLinks[0].href;
        document.documentElement.dataset.signalSpotifyPlayActivated = '1';
        playbackControls[0].click();
        return 'spotify_play_dispatched';
      } catch (_) {
        return 'spotify_skip_unconfirmed';
      }
    })()
    """

    private static let spotifyPlaybackConfirmationJavaScript = """
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'open.spotify.com') {
        return 'wrong_origin';
      }
      try {
        const isVisible = (element) => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 0 && rect.height > 0 &&
            style.visibility !== 'hidden' && style.display !== 'none' &&
            element.getAttribute('aria-hidden') !== 'true' &&
            !element.disabled;
        };
        const before =
          document.documentElement.dataset.signalSpotifyTrackBefore;
        const after =
          document.documentElement.dataset.signalSpotifyTrackAfter;
        const playActivated =
          document.documentElement.dataset.signalSpotifyPlayActivated;
        delete document.documentElement.dataset.signalSpotifyTrackBefore;
        delete document.documentElement.dataset.signalSpotifyTrackAfter;
        delete document.documentElement.dataset.signalSpotifyPlayActivated;
        const trackLinks = Array.from(document.querySelectorAll(
          `[data-testid='now-playing-widget']
           a[data-testid='context-item-link'][href*='/track/']`
        )).filter(isVisible);
        if (
          !before || !after || playActivated !== '1' ||
          trackLinks.length !== 1 ||
          after === before ||
          trackLinks[0].href !== after
        ) {
          return 'spotify_skip_unconfirmed';
        }
        const playbackControls = Array.from(document.querySelectorAll(
          `button[data-testid='control-button-playpause']`
        )).filter(isVisible);
        if (playbackControls.length !== 1) {
          return 'spotify_skip_unconfirmed';
        }
        const playbackLabel = (
          playbackControls[0].getAttribute('aria-label') ||
          playbackControls[0].getAttribute('title') ||
          ''
        ).trim().toLowerCase();
        return playbackLabel === 'pause'
          ? 'spotify_skipped'
          : 'spotify_skip_unconfirmed';
      } catch (_) {
        return 'spotify_skip_unconfirmed';
      }
    })()
    """

    private static func makeChromeProgram(
        exactHost: String,
        tabURLPrefix: String,
        missingTabResult: String,
        javaScript: String
    ) -> String {
        let rootURL = String(tabURLPrefix.dropLast())
        let encodedJavaScript = appleScriptStringLiteral(javaScript)
        return """
        tell application id "com.google.Chrome"
            if not running then return "chrome_unavailable"
            repeat with attemptNumber from 1 to 20
                repeat with browserWindow in windows
                    set candidateIndex to 0
                    repeat with browserTab in tabs of browserWindow
                        set candidateIndex to candidateIndex + 1
                        set candidateURL to URL of browserTab
                        if candidateURL is "\(rootURL)" or candidateURL starts with "\(tabURLPrefix)" then
                            set active tab index of browserWindow to candidateIndex
                            set index of browserWindow to 1
                            activate
                            delay 0.05
                            set verifiedURL to URL of active tab of front window
                            if not (verifiedURL is "\(rootURL)" or verifiedURL starts with "\(tabURLPrefix)") then
                                return "wrong_origin"
                            end if
                            try
                                return (execute active tab of front window javascript "\(encodedJavaScript)")
                            on error errorMessage number errorNumber
                                if errorMessage contains "JavaScript from Apple Events" then
                                    return "javascript_permission_required"
                                end if
                                error errorMessage number errorNumber
                            end try
                        end if
                    end repeat
                end repeat
                delay 0.1
            end repeat
            return "\(missingTabResult)"
        end tell
        -- The page program performs a second, exact check for \(exactHost).
        """
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

protocol ChromeAutomationScriptExecuting: Sendable {
    func execute(
        _ program: ChromeAutomationFixedProgram
    ) async throws -> String
}

final class ChromeAutomationCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func checkCancellation() throws {
        lock.lock()
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel {
            throw CancellationError()
        }
    }
}

protocol ChromeAutomationFixedScriptRunning: Sendable {
    func run(
        _ program: ChromeAutomationFixedProgram,
        cancellationGate: ChromeAutomationCancellationGate
    ) throws -> String
}

protocol ChromeAutomationExecutionQueueing: Sendable {
    func enqueue(_ operation: @escaping @Sendable () -> Void)
}

private struct DispatchChromeAutomationExecutionQueue:
    ChromeAutomationExecutionQueueing,
    Sendable
{
    let queue: DispatchQueue

    func enqueue(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
}

private struct LiveNSAppleScriptChromeAutomationRunner:
    ChromeAutomationFixedScriptRunning,
    Sendable
{
    func run(
        _ program: ChromeAutomationFixedProgram,
        cancellationGate: ChromeAutomationCancellationGate
    ) throws -> String {
        try cancellationGate.checkCancellation()
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: NSWorkspaceHTTPSURLLauncher.chromeBundleIdentifier
        ) != nil else {
            throw ChromeAutomationError.chromeUnavailable
        }
        guard let script = NSAppleScript(source: program.source) else {
            throw ChromeAutomationError.scriptCompilationFailed
        }

        try requireChromeAutomationPermission()

        // This is the final cancellation boundary before the Apple Event can
        // cause a browser-side effect. NSAppleScript has no supported API for
        // interrupting executeAndReturnError once that call has begun.
        try cancellationGate.checkCancellation()
        var errorInfo: NSDictionary?
        let response = script.executeAndReturnError(&errorInfo)
        try cancellationGate.checkCancellation()

        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            let errorMessage =
                errorInfo[NSAppleScript.errorMessage] as? String ?? ""
            if errorNumber == -1_743 {
                throw ChromeAutomationError.automationPermissionRequired
            }
            if errorNumber == -600 {
                throw ChromeAutomationError.chromeUnavailable
            }
            if errorMessage.localizedCaseInsensitiveContains(
                "JavaScript from Apple Events"
            ) {
                throw ChromeAutomationError.javaScriptFromAppleEventsDisabled
            }
            throw ChromeAutomationError.scriptExecutionFailed
        }
        guard let result = response.stringValue else {
            throw ChromeAutomationError.unexpectedResult
        }
        return result
    }

    private func requireChromeAutomationPermission() throws {
        var chromeTarget = AEAddressDesc()
        let identifier = Array(
            NSWorkspaceHTTPSURLLauncher.chromeBundleIdentifier.utf8
        )
        let creationStatus = identifier.withUnsafeBytes { buffer in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                buffer.baseAddress,
                buffer.count,
                &chromeTarget
            )
        }
        guard creationStatus == noErr else {
            throw ChromeAutomationError.scriptExecutionFailed
        }
        defer {
            AEDisposeDesc(&chromeTarget)
        }

        let permissionStatus = AEDeterminePermissionToAutomateTarget(
            &chromeTarget,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        switch permissionStatus {
        case noErr:
            return
        case OSStatus(errAEEventNotPermitted):
            throw ChromeAutomationError.automationPermissionRequired
        case OSStatus(procNotFound):
            throw ChromeAutomationError.chromeUnavailable
        default:
            throw ChromeAutomationError.scriptExecutionFailed
        }
    }
}

struct NSAppleScriptChromeAutomationExecutor:
    ChromeAutomationScriptExecuting,
    Sendable
{
    private static let liveExecutionQueue = DispatchQueue(
        label: "com.signal.chrome-automation.fixed-programs",
        qos: .userInitiated
    )

    private let runner: any ChromeAutomationFixedScriptRunning
    private let executionQueue: any ChromeAutomationExecutionQueueing

    init() {
        runner = LiveNSAppleScriptChromeAutomationRunner()
        executionQueue = DispatchChromeAutomationExecutionQueue(
            queue: Self.liveExecutionQueue
        )
    }

    init(
        runner: any ChromeAutomationFixedScriptRunning,
        executionQueue: DispatchQueue
    ) {
        self.runner = runner
        self.executionQueue = DispatchChromeAutomationExecutionQueue(
            queue: executionQueue
        )
    }

    init(
        runner: any ChromeAutomationFixedScriptRunning,
        executionQueue: any ChromeAutomationExecutionQueueing
    ) {
        self.runner = runner
        self.executionQueue = executionQueue
    }

    func execute(
        _ program: ChromeAutomationFixedProgram
    ) async throws -> String {
        try Task.checkCancellation()
        let cancellationGate = ChromeAutomationCancellationGate()
        let result: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                executionQueue.enqueue {
                    do {
                        try cancellationGate.checkCancellation()
                        let result = try runner.run(
                            program,
                            cancellationGate: cancellationGate
                        )
                        try cancellationGate.checkCancellation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellationGate.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}

public struct ChromeAutomationAdapter: ChromeAutomationAdapting, Sendable {
    private let scriptExecutor: any ChromeAutomationScriptExecuting
    private let spotifyVerificationDelay: Duration

    public init() {
        scriptExecutor = NSAppleScriptChromeAutomationExecutor()
        spotifyVerificationDelay = .milliseconds(750)
    }

    init(
        scriptExecutor: any ChromeAutomationScriptExecuting,
        spotifyVerificationDelay: Duration = .zero
    ) {
        self.scriptExecutor = scriptExecutor
        self.spotifyVerificationDelay = spotifyVerificationDelay
    }

    public func submitReviewedBoltPrompt(
        context: SignalCommandExecutionContext
    ) async throws -> ChromeAutomationOutcome {
        try context.checkCancellation()
        let result = try await scriptExecutor.execute(.boltReviewedPrompt)
        switch result {
        case "bolt_submitted":
            return .boltPromptSubmitted
        case "chrome_unavailable":
            throw ChromeAutomationError.chromeUnavailable
        case "javascript_permission_required":
            throw ChromeAutomationError.javaScriptFromAppleEventsDisabled
        case "bolt_tab_unavailable":
            throw ChromeAutomationError.boltTabUnavailable
        case "bolt_field_unavailable", "wrong_origin":
            throw ChromeAutomationError.boltFieldUnavailable
        case "bolt_submit_unavailable":
            throw ChromeAutomationError.boltSubmitUnavailable
        default:
            throw ChromeAutomationError.unexpectedResult
        }
    }

    public func skipSpotifyWebTrack(
        context: SignalCommandExecutionContext
    ) async throws -> ChromeAutomationOutcome {
        try context.checkCancellation()
        let dispatchResult = try await scriptExecutor.execute(.spotifyNextTrack)
        switch dispatchResult {
        case "spotify_click_dispatched":
            break
        case "chrome_unavailable":
            throw ChromeAutomationError.chromeUnavailable
        case "javascript_permission_required":
            throw ChromeAutomationError.javaScriptFromAppleEventsDisabled
        case "spotify_tab_unavailable", "wrong_origin":
            throw ChromeAutomationError.spotifyTabUnavailable
        case "spotify_next_control_unavailable":
            throw ChromeAutomationError.spotifyNextControlUnavailable
        case "spotify_track_identity_unavailable":
            throw ChromeAutomationError.spotifyTrackIdentityUnavailable
        default:
            throw ChromeAutomationError.unexpectedResult
        }

        try context.checkCancellation()
        try await ContinuousClock().sleep(for: spotifyVerificationDelay)
        try context.checkCancellation()
        let verificationResult = try await scriptExecutor.execute(
            .spotifyVerifyNextTrack
        )
        switch verificationResult {
        case "spotify_skipped":
            return .spotifyTrackSkipped
        case "spotify_play_dispatched":
            break
        case "chrome_unavailable":
            throw ChromeAutomationError.chromeUnavailable
        case "javascript_permission_required":
            throw ChromeAutomationError.javaScriptFromAppleEventsDisabled
        case "spotify_tab_unavailable", "wrong_origin":
            throw ChromeAutomationError.spotifyTabUnavailable
        case "spotify_track_identity_unavailable":
            throw ChromeAutomationError.spotifyTrackIdentityUnavailable
        case "spotify_skip_unconfirmed":
            throw ChromeAutomationError.spotifySkipUnconfirmed
        default:
            throw ChromeAutomationError.unexpectedResult
        }

        try context.checkCancellation()
        try await ContinuousClock().sleep(for: spotifyVerificationDelay)
        try context.checkCancellation()
        let playbackConfirmationResult = try await scriptExecutor.execute(
            .spotifyConfirmPlayback
        )
        switch playbackConfirmationResult {
        case "spotify_skipped":
            return .spotifyTrackSkipped
        case "chrome_unavailable":
            throw ChromeAutomationError.chromeUnavailable
        case "javascript_permission_required":
            throw ChromeAutomationError.javaScriptFromAppleEventsDisabled
        case "spotify_tab_unavailable", "wrong_origin":
            throw ChromeAutomationError.spotifyTabUnavailable
        case "spotify_skip_unconfirmed":
            throw ChromeAutomationError.spotifySkipUnconfirmed
        default:
            throw ChromeAutomationError.unexpectedResult
        }
    }
}
