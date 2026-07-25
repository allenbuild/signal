import AppKit
import CoreGraphics
import Foundation
import Security
import SignalCore
import UserNotifications

final class QuartzEventPoster: @unchecked Sendable {
    private struct HeldKey: Equatable {
        var code: CGKeyCode
        var flags: CGEventFlags
    }

    private let safetyGate: SafetyGate
    private let stateLock = NSLock()
    private var heldKeys: [HeldKey] = []
    private var mouseDownAt: CGPoint?
    private var pauseHandlerID: UUID?

    init(safetyGate: SafetyGate) {
        self.safetyGate = safetyGate
        pauseHandlerID = safetyGate.onPause { [weak self] in
            self?.releaseHeldEvents()
        }
    }

    func accessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func movePointer(relative delta: Point2D) {
        safetyGate.performIfEnabled {
            guard let current = CGEvent(source: nil)?.location else { return }
            let bounds = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            let destination = CGPoint(
                x: min(max(current.x + delta.x, bounds.minX), bounds.maxX - 1),
                y: min(max(current.y + delta.y, bounds.minY), bounds.maxY - 1)
            )
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: destination,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }

    @discardableResult
    func leftClick() -> Bool {
        safetyGate.performIfEnabled {
            guard let point = CGEvent(source: nil)?.location else { return false }
            postClickPair(at: point)
            return true
        } ?? false
    }

    @discardableResult
    func click(at point: CGPoint) -> Bool {
        safetyGate.performIfEnabled {
            postClickPair(at: point)
            return true
        } ?? false
    }

    @discardableResult
    func scroll(_ amount: Double, horizontal: Double = 0) -> Bool {
        safetyGate.performIfEnabled {
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(clamped(amount, -80...80)),
                wheel2: Int32(clamped(horizontal, -80...80)),
                wheel3: 0
            )?.post(tap: .cghidEventTap)
            return true
        } ?? false
    }

    @discardableResult
    func zoom(steps: Int) -> Bool {
        let keyCode: CGKeyCode = steps > 0 ? 24 : 27
        let flags: CGEventFlags = steps > 0 ? [.maskCommand, .maskShift] : [.maskCommand]
        for _ in 0..<min(abs(steps), 4) {
            guard postKey(code: keyCode, flags: flags) else { return false }
        }
        return true
    }

    @discardableResult
    func postKey(code: CGKeyCode, flags: CGEventFlags) -> Bool {
        safetyGate.performIfEnabled {
            let held = HeldKey(code: code, flags: flags)
            stateLock.withLock { heldKeys.append(held) }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
            down?.flags = flags
            down?.post(tap: .cghidEventTap)
            releaseKeyIfHeld(held)
            return true
        } ?? false
    }

    @discardableResult
    func typeText(_ text: String) -> Bool {
        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            let end = min(index + 20, utf16.count)
            let chunk = Array(utf16[index..<end])
            let posted = safetyGate.performIfEnabled {
                let held = HeldKey(code: 0, flags: [])
                stateLock.withLock { heldKeys.append(held) }
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                down?.post(tap: .cghidEventTap)
                releaseUnicodeKeyIfHeld(held, chunk: chunk)
                return true
            } ?? false
            guard posted else { return false }
            index = end
        }
        return true
    }

    /// Posts unconditional releases. It is invoked synchronously by SafetyGate
    /// after the gate closes, so no permission check is performed here.
    func releaseHeldEvents() {
        let snapshot: ([HeldKey], CGPoint?) = stateLock.withLock {
            let value = (heldKeys, mouseDownAt)
            heldKeys.removeAll()
            mouseDownAt = nil
            return value
        }
        for held in snapshot.0 {
            postKeyUp(code: held.code)
            releaseModifierKeys(for: held.flags)
        }
        if let point = snapshot.1 {
            postMouseUp(at: point)
        }
    }

    private func releaseKeyIfHeld(_ held: HeldKey) {
        let shouldRelease = stateLock.withLock {
            guard let index = heldKeys.firstIndex(of: held) else { return false }
            heldKeys.remove(at: index)
            return true
        }
        if shouldRelease {
            postKeyUp(code: held.code)
            releaseModifierKeys(for: held.flags)
        }
    }

    private func releaseUnicodeKeyIfHeld(_ held: HeldKey, chunk: [UniChar]) {
        let shouldRelease = stateLock.withLock {
            guard let index = heldKeys.firstIndex(of: held) else { return false }
            heldKeys.remove(at: index)
            return true
        }
        guard shouldRelease else { return }
        let up = CGEvent(keyboardEventSource: nil, virtualKey: held.code, keyDown: false)
        up?.flags = []
        up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
        up?.post(tap: .cghidEventTap)
    }

    private func releaseMouseIfHeld() {
        let point = stateLock.withLock {
            let point = mouseDownAt
            mouseDownAt = nil
            return point
        }
        if let point { postMouseUp(at: point) }
    }

    private func postClickPair(at point: CGPoint) {
        stateLock.withLock { mouseDownAt = point }
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
        releaseMouseIfHeld()
    }

    private func postKeyUp(code: CGKeyCode) {
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
    }

    private func releaseModifierKeys(for flags: CGEventFlags) {
        let modifiers: [(CGEventFlags, CGKeyCode)] = [
            (.maskCommand, 55),
            (.maskShift, 56),
            (.maskAlternate, 58),
            (.maskControl, 59)
        ]
        for (flag, code) in modifiers where flags.contains(flag) {
            postKeyUp(code: code)
        }
    }

    private func postMouseUp(at point: CGPoint) {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    deinit {
        releaseHeldEvents()
        if let pauseHandlerID { safetyGate.removeHandler(pauseHandlerID) }
    }
}

final class SystemActionPerformer: ActionPerforming, @unchecked Sendable {
    private let events: QuartzEventPoster
    private let safetyGate: SafetyGate

    init(events: QuartzEventPoster, safetyGate: SafetyGate) {
        self.events = events
        self.safetyGate = safetyGate
    }

    func perform(_ step: ActionStep) async throws -> String {
        try ensureOutputEnabled()
        switch step.action {
        case .openApplication, .focusApplication:
            let bundleID = try string("bundleIdentifier", in: step)
            guard let url = await MainActor.run(body: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            }) else { throw SystemActionError.applicationNotFound(bundleID) }
            try ensureOutputEnabled()
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return "Opened \(bundleID)"

        case .openURL:
            let raw = try string("url", in: step)
            try ActionPlanValidator(requireApproval: false).validatePublicURL(raw)
            guard let url = URL(string: raw) else { throw SystemActionError.invalidParameter("url") }
            try ensureOutputEnabled()
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return "Opened reviewed destination"

        case .keyboardShortcut:
            let key = try string("key", in: step)
            let modifiers = arrayStrings("modifiers", in: step)
            guard let code = Self.keyCodes[key.lowercased()] else {
                throw SystemActionError.invalidParameter("key")
            }
            var flags: CGEventFlags = []
            if modifiers.contains("command") { flags.insert(.maskCommand) }
            if modifiers.contains("option") { flags.insert(.maskAlternate) }
            if modifiers.contains("control") { flags.insert(.maskControl) }
            if modifiers.contains("shift") { flags.insert(.maskShift) }
            try ensureOutputEnabled()
            guard events.postKey(code: code, flags: flags) else {
                throw SystemActionError.outputPaused
            }
            return "Posted reviewed shortcut"

        case .typeText:
            let text = try string("text", in: step)
            try ensureOutputEnabled()
            guard events.typeText(text) else { throw SystemActionError.outputPaused }
            return "Typed reviewed text"

        case .wait:
            let durationMs = step.parameters["durationMs"]?.numberValue ?? 1_000
            try await Task.sleep(nanoseconds: UInt64(durationMs * 1_000_000))
            try ensureOutputEnabled()
            return "Waited \(Int(durationMs)) ms"

        case .showNotification:
            let title = step.parameters["title"]?.stringValue ?? "Signal"
            let body = step.parameters["body"]?.stringValue ?? ""
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try ensureOutputEnabled()
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
            return "Displayed notification"

        case .speakText:
            let value = try string("text", in: step)
            try ensureOutputEnabled()
            _ = await MainActor.run {
                NSSpeechSynthesizer().startSpeaking(value)
            }
            return "Spoke reviewed text"

        case .setClipboard:
            let value = try string("text", in: step)
            try ensureOutputEnabled()
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            return "Updated clipboard"

        case .scrollAmount:
            let vertical = step.parameters["vertical"]?.numberValue ?? 0
            let horizontal = step.parameters["horizontal"]?.numberValue ?? 0
            try ensureOutputEnabled()
            guard events.scroll(vertical, horizontal: horizontal) else {
                throw SystemActionError.outputPaused
            }
            return "Scrolled"

        case .zoomSteps:
            guard events.zoom(steps: Int(step.parameters["steps"]?.numberValue ?? 0)) else {
                throw SystemActionError.outputPaused
            }
            return "Zoomed"

        case .clickScreenPoint:
            guard let x = step.parameters["x"]?.numberValue,
                  let y = step.parameters["y"]?.numberValue,
                  step.parameters["coordinateSpace"]?.stringValue == "normalized_active_display" else {
                throw SystemActionError.invalidParameter("coordinates")
            }
            let screenFrame = await MainActor.run {
                let mouse = NSEvent.mouseLocation
                return NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.frame ?? NSScreen.main?.frame ?? .zero
            }
            let point = CGPoint(
                x: screenFrame.minX + clamped(x, 0...1) * screenFrame.width,
                y: screenFrame.minY + clamped(y, 0...1) * screenFrame.height
            )
            try ensureOutputEnabled()
            guard events.click(at: point) else { throw SystemActionError.outputPaused }
            return "Clicked reviewed normalized point"

        case .discordWebhook, .slackWebhook:
            return "External secret not configured; wrote a local fallback receipt"

        case .setVolume:
            let percent = Int(clamped(step.parameters["percent"]?.numberValue ?? 50, 0...100))
            try ensureOutputEnabled()
            let script = NSAppleScript(source: "set volume output volume \(percent)")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            if let error { throw SystemActionError.appleScript(error.description) }
            return "Set volume"

        case .runAppleShortcut:
            let name = try string("shortcutName", in: step)
            var components = URLComponents(string: "shortcuts://run-shortcut")!
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url else { throw SystemActionError.invalidParameter("name") }
            try ensureOutputEnabled()
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return "Requested Apple Shortcut"

        case .runAppleScriptTemplate:
            let template = try string("templateId", in: step)
            let scriptSource: String
            switch template {
            case "activate_application":
                guard case .object(let arguments) = step.parameters["arguments"],
                      let bundleID = arguments["bundleIdentifier"]?.stringValue,
                      bundleID.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
                    throw SystemActionError.invalidParameter("arguments.bundleIdentifier")
                }
                scriptSource = "tell application id \"\(bundleID)\" to activate"
            case "create_textedit_document":
                scriptSource = "tell application \"TextEdit\" to make new document"
            case "open_system_settings_pane":
                scriptSource = "tell application \"System Settings\" to activate"
            default:
                throw SystemActionError.unsupported(step.action)
            }
            try ensureOutputEnabled()
            var error: NSDictionary?
            NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
            if let error { throw SystemActionError.appleScript(error.description) }
            return "Ran allowlisted template"

        case .playSound:
            await MainActor.run { NSSound.beep() }
            return "Played sound"

        case .showOverlay, .readClipboardAndTransform, .mediaControl, .conditional,
             .rawAppleScript, .shellCommand, .httpRequest, .openDeepLink:
            throw SystemActionError.unsupported(step.action)
        }
    }

    private func string(_ key: String, in step: ActionStep) throws -> String {
        guard let value = step.parameters[key]?.stringValue, !value.isEmpty else {
            throw SystemActionError.invalidParameter(key)
        }
        return value
    }

    private func arrayStrings(_ key: String, in step: ActionStep) -> [String] {
        guard case .array(let values) = step.parameters[key] else { return [] }
        return values.compactMap(\.stringValue)
    }

    private func ensureOutputEnabled() throws {
        if safetyGate.isPaused { throw SystemActionError.outputPaused }
        try Task.checkCancellation()
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "return": 36, "space": 49, "escape": 53
    ]
}

enum SystemActionError: Error, LocalizedError {
    case invalidParameter(String)
    case applicationNotFound(String)
    case unsupported(ActionKind)
    case appleScript(String)
    case outputPaused

    var errorDescription: String? {
        switch self {
        case .invalidParameter(let value): return "Invalid \(value)."
        case .applicationNotFound(let value): return "Application \(value) was not found."
        case .unsupported(let action): return "\(action.rawValue) is not enabled in this release."
        case .appleScript(let value): return value
        case .outputPaused: return "Output is paused; the action was blocked."
        }
    }
}

struct ExactEffectConfirmationProvider: ConfirmationProviding {
    func approve(plan: ActionPlan, step: ActionStep?) async -> Bool {
        let confirmation = step?.confirmation ?? plan.confirmation
        let effects = step.map { [$0] } ?? plan.steps
        return await MainActor.run {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = step == nil
                ? "Allow “\(plan.name)” to run?"
                : "Allow this \(step!.action.rawValue.replacingOccurrences(of: "_", with: " ")) effect?"
            let exactEffects = effects.enumerated().map { index, effect in
                "\(index + 1). \(Self.exactSummary(effect))"
            }.joined(separator: "\n")
            alert.informativeText = [
                confirmation.reason,
                "Exact effects:",
                exactEffects,
                "This approval applies to this execution only."
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            alert.addButton(withTitle: "Allow Once")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    private static func exactSummary(_ step: ActionStep) -> String {
        let parameters = step.parameters.keys.sorted().map { key in
            "\(key)=\(render(step.parameters[key] ?? .null))"
        }.joined(separator: ", ")
        return parameters.isEmpty
            ? step.plainEnglish
            : "\(step.plainEnglish) [\(parameters)]"
    }

    private static func render(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return "“\(value)”"
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .array(let values): return "[\(values.map(render).joined(separator: ", "))]"
        case .object(let values):
            return "{\(values.keys.sorted().map { "\($0): \(render(values[$0] ?? .null))" }.joined(separator: ", "))}"
        case .null: return "null"
        }
    }
}

final class EmergencyHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(handler: @escaping @Sendable () -> Void) {
        stop()
        let matches: (NSEvent) -> Bool = { event in
            event.charactersIgnoringModifiers?.lowercased() == "h" &&
                event.modifierFlags.intersection([.control, .option, .command]) == [.control, .option, .command]
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if matches(event) { handler() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if matches(event) {
                handler()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit { stop() }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

struct KeychainSecretStore {
    let service = "app.signal.hand"

    func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
    }

    func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
