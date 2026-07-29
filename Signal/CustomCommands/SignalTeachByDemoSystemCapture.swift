@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
public final class SignalTeachByDemoSystemClock:
    SignalTeachByDemoCaptureClock
{
    public init() {}

    public var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

@MainActor
public final class SignalTeachByDemoTimerScheduler:
    SignalTeachByDemoCaptureScheduling
{
    private var timer: Timer?

    public init() {}

    public func startRepeating(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        stop()
        timer = Timer.scheduledTimer(
            withTimeInterval: max(0.05, interval),
            repeats: true
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
public final class SignalTeachByDemoDisabledLocalPreview:
    SignalTeachByDemoLocalPreviewing
{
    public init() {}
    public func startLocalPreview() throws {}
    public func stopLocalPreview() {}
}

@MainActor
public final class SignalTeachByDemoWorkspaceObserver:
    SignalTeachByDemoApplicationObserving
{
    private var activationToken: NSObjectProtocol?
    private var handler:
        (@MainActor (SignalTeachByDemoApplication) -> Void)?

    public init() {}

    public var frontmostApplication: SignalTeachByDemoApplication? {
        NSWorkspace.shared.frontmostApplication.flatMap(Self.application)
    }

    public func start(
        handler: @escaping @MainActor (SignalTeachByDemoApplication) -> Void
    ) {
        stop()
        self.handler = handler
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let runningApplication =
                notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication else {
                return
            }
            MainActor.assumeIsolated {
                guard let application = Self.application(
                    runningApplication
                ) else {
                    return
                }
                self?.handler?(application)
            }
        }
    }

    public func stop() {
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(
                activationToken
            )
        }
        activationToken = nil
        handler = nil
    }

    private static func application(
        _ application: NSRunningApplication
    ) -> SignalTeachByDemoApplication? {
        guard let bundleIdentifier = application.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }
        return SignalTeachByDemoApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: application.localizedName ?? bundleIdentifier
        )
    }
}

public struct SignalTeachByDemoReviewedTargetKey:
    Hashable,
    Sendable
{
    public var applicationBundleIdentifier: String
    public var role: String
    public var title: String
    public var identifier: String?

    public init(
        applicationBundleIdentifier: String,
        role: String,
        title: String,
        identifier: String?
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.role = role
        self.title = title
        self.identifier = identifier
    }

    public init(target: SignalReviewedAccessibilityTarget) {
        self.init(
            applicationBundleIdentifier:
                target.applicationBundleIdentifier,
            role: target.role,
            title: target.title,
            identifier: target.identifier
        )
    }
}

@MainActor
public final class SignalTeachByDemoReviewContext {
    private var reviewedApplications: Set<String> = []
    private var reviewedTargets: Set<SignalTeachByDemoReviewedTargetKey> = []
    private var reviewedURLs: [String: String] = [:]
    private let urlPolicy: SignalCommandURLPolicy

    public init(urlPolicy: SignalCommandURLPolicy = .init()) {
        self.urlPolicy = urlPolicy
    }

    public func reviewApplication(bundleIdentifier: String) {
        guard Self.isSafeBundleIdentifier(bundleIdentifier) else { return }
        reviewedApplications.insert(bundleIdentifier)
    }

    public func reviewTarget(
        _ target: SignalReviewedAccessibilityTarget
    ) {
        guard !target.isSecureField,
              Self.isSafeBundleIdentifier(
                  target.applicationBundleIdentifier
              ) else {
            return
        }
        reviewedApplications.insert(target.applicationBundleIdentifier)
        reviewedTargets.insert(.init(target: target))
    }

    public func reviewHTTPSURL(
        _ rawURL: String,
        forApplication bundleIdentifier: String
    ) throws {
        guard Self.isSafeBundleIdentifier(bundleIdentifier) else {
            throw SignalCommandValidationError.invalidField(
                path: "application.bundleIdentifier",
                reason: "invalid bundle identifier"
            )
        }
        let url = try urlPolicy.validate(rawURL)
        reviewedApplications.insert(bundleIdentifier)
        reviewedURLs[bundleIdentifier] = url.absoluteString
    }

    public func revokeAll() {
        reviewedApplications = []
        reviewedTargets = []
        reviewedURLs = [:]
    }

    fileprivate func isApplicationReviewed(_ bundleIdentifier: String) -> Bool {
        reviewedApplications.contains(bundleIdentifier)
    }

    fileprivate func isTargetReviewed(
        _ target: SignalReviewedAccessibilityTarget
    ) -> Bool {
        reviewedTargets.contains(.init(target: target))
    }

    fileprivate func reviewedURL(for bundleIdentifier: String) -> String? {
        reviewedURLs[bundleIdentifier]
    }

    private static func isSafeBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 255
            && value.contains(".")
            && value.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn:
                        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
                ).contains($0)
            }
    }
}

@MainActor
public final class SignalTeachByDemoAXContextResolver:
    SignalTeachByDemoContextResolving
{
    private let reviewContext: SignalTeachByDemoReviewContext

    public init(reviewContext: SignalTeachByDemoReviewContext) {
        self.reviewContext = reviewContext
    }

    public func isApplicationReviewed(
        _ application: SignalTeachByDemoApplication
    ) -> Bool {
        reviewContext.isApplicationReviewed(application.bundleIdentifier)
    }

    public func target(
        at point: SignalTeachByDemoScreenPoint,
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &element
        )
        guard error == .success, let element,
              belongs(element, to: application) else {
            return nil
        }
        return resolvedTarget(from: element, application: application)
    }

    public func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget? {
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let focused: AXUIElement = attribute(
            kAXFocusedUIElementAttribute,
            from: applicationElement
        ) else {
            return nil
        }
        return resolvedTarget(from: focused, application: application)
    }

    public func reviewedHTTPSURL(
        for application: SignalTeachByDemoApplication
    ) -> String? {
        reviewContext.reviewedURL(for: application.bundleIdentifier)
    }

    /// Returns an unapproved candidate for explicit UI review. Merely
    /// inspecting it does not authorize capture.
    public func inspectTarget(
        at point: SignalTeachByDemoScreenPoint,
        in application: SignalTeachByDemoApplication
    ) -> SignalReviewedAccessibilityTarget? {
        target(at: point, in: application)?.target
    }

    /// Returns an unapproved focused candidate for explicit UI review.
    public func inspectFocusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalReviewedAccessibilityTarget? {
        focusedTarget(in: application)?.target
    }

    private func resolvedTarget(
        from element: AXUIElement,
        application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget? {
        guard let role: String = attribute(kAXRoleAttribute, from: element),
              !role.isEmpty else {
            return nil
        }
        let title: String =
            attribute(kAXTitleAttribute, from: element)
            ?? attribute(kAXDescriptionAttribute, from: element)
            ?? "Untitled target"
        let identifier: String? = attribute(
            kAXIdentifierAttribute,
            from: element
        )
        let subrole: String? = attribute(kAXSubroleAttribute, from: element)
        let isSecure = role.caseInsensitiveCompare(
            "AXSecureTextField"
        ) == .orderedSame
            || subrole?.localizedCaseInsensitiveContains("secure") == true

        let target = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: application.bundleIdentifier,
            role: Self.safeText(role, fallback: "AXUnknown"),
            title: isSecure
                ? "Secure field"
                : Self.safeText(title, fallback: "Untitled target"),
            identifier: isSecure
                ? nil
                : identifier.map {
                    Self.safeText($0, fallback: "")
                },
            isSecureField: isSecure,
            wasUserReviewed: false
        )
        return SignalTeachByDemoResolvedTarget(
            target: target,
            isReviewed: !isSecure
                && reviewContext.isTargetReviewed(target)
        )
    }

    private func belongs(
        _ element: AXUIElement,
        to application: SignalTeachByDemoApplication
    ) -> Bool {
        var processIdentifier: pid_t = 0
        return AXUIElementGetPid(element, &processIdentifier) == .success
            && processIdentifier == application.processIdentifier
    }

    private func attribute<Value>(
        _ name: String,
        from element: AXUIElement
    ) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? Value
    }

    private static func safeText(
        _ value: String,
        fallback: String
    ) -> String {
        let filtered = String(
            value.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }
        )
        let limited = String(filtered.prefix(200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? fallback : limited
    }
}

@MainActor
public final class SignalTeachByDemoCGEventTap:
    SignalTeachByDemoEventCapturing
{
    private let backend: SignalTeachByDemoCGEventTapBackend

    public init(ignoredEventMarker: Int64? = nil) {
        backend = SignalTeachByDemoCGEventTapBackend(
            ignoredEventMarker: ignoredEventMarker
        )
    }

    public func start(
        handler: @escaping @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    ) throws {
        try backend.start(handler: handler)
    }

    public func stop() {
        backend.stop()
    }
}

/// Core Graphics invokes its C callback on the run loop where the tap is
/// installed. The public main-actor wrapper is the only caller; unchecked
/// Sendable prevents importing Core Foundation reference types into the
/// coordinator's concurrency surface.
private final class SignalTeachByDemoCGEventTapBackend:
    @unchecked Sendable
{
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackBox: SignalTeachByDemoEventTapCallbackBox?
    private let ignoredEventMarker: Int64?

    init(ignoredEventMarker: Int64?) {
        self.ignoredEventMarker = ignoredEventMarker
    }

    func start(
        handler: @escaping @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    ) throws {
        stop()
        let box = SignalTeachByDemoEventTapCallbackBox(
            ignoredEventMarker: ignoredEventMarker,
            handler: handler
        )
        let mask = SignalTeachByDemoCGEventTranslator.mask(for: [
            .leftMouseUp,
            .keyDown,
        ])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<
                    SignalTeachByDemoEventTapCallbackBox
                >.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout
                    || type == .tapDisabledByUserInput {
                    box.reenableTap()
                    return Unmanaged.passUnretained(event)
                }
                if !box.shouldCapture(event) {
                    return Unmanaged.passUnretained(event)
                }
                if let captured =
                    SignalTeachByDemoCGEventTranslator.capture(
                        type: type,
                        event: event
                    ) {
                    box.emit(captured)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else {
            throw SignalTeachByDemoCaptureError.eventTapUnavailable
        }
        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        ) else {
            CFMachPortInvalidate(tap)
            throw SignalTeachByDemoCaptureError.eventTapUnavailable
        }

        callbackBox = box
        eventTap = tap
        runLoopSource = source
        box.setTap(tap)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        callbackBox?.setTap(nil)
        runLoopSource = nil
        eventTap = nil
        callbackBox = nil
    }
}

private enum SignalTeachByDemoCGEventTranslator {
    static func mask(
        for types: [CGEventType]
    ) -> CGEventMask {
        types.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << CGEventMask($1.rawValue))
        }
    }

    static func capture(
        type: CGEventType,
        event: CGEvent
    ) -> SignalTeachByDemoCapturedEvent? {
        switch type {
        case .leftMouseUp:
            let location = event.location
            return .primaryPointerReleased(
                at: .init(x: location.x, y: location.y)
            )
        case .keyDown:
            if IsSecureEventInputEnabled() {
                return .secureKeyboardInput
            }
            let isRepeat = event.getIntegerValueField(
                .keyboardEventAutorepeat
            ) != 0
            let keyCode = event.getIntegerValueField(
                .keyboardEventKeycode
            )
            return .keyDown(
                keyCode: keyCode,
                text: unicodeText(from: event),
                modifiers: modifiers(from: event.flags),
                isRepeat: isRepeat
            )
        default:
            return nil
        }
    }

    private static func unicodeText(
        from event: CGEvent
    ) -> String? {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 32)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &length,
            unicodeString: &characters
        )
        guard length > 0 else { return nil }
        return String(
            utf16CodeUnits: characters,
            count: min(length, characters.count)
        )
    }

    private static func modifiers(
        from flags: CGEventFlags
    ) -> Set<SignalTeachByDemoModifier> {
        var result: Set<SignalTeachByDemoModifier> = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }
}

private final class SignalTeachByDemoEventTapCallbackBox:
    @unchecked Sendable
{
    private let ignoredEventMarker: Int64?
    private let handler:
        @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    private var eventTap: CFMachPort?

    init(
        ignoredEventMarker: Int64?,
        handler:
            @escaping @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    ) {
        self.ignoredEventMarker = ignoredEventMarker
        self.handler = handler
    }

    func shouldCapture(_ event: CGEvent) -> Bool {
        guard let ignoredEventMarker else { return true }
        return event.getIntegerValueField(.eventSourceUserData)
            != ignoredEventMarker
    }

    func setTap(_ eventTap: CFMachPort?) {
        self.eventTap = eventTap
    }

    func reenableTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func emit(_ event: SignalTeachByDemoCapturedEvent) {
        handler(event)
    }
}
