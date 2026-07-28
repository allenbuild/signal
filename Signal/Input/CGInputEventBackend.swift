@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class SystemInputTrustProvider: InputTrustProviding, @unchecked Sendable {
    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }
}

public final class CGInputEventBackend: InputEventBackend, @unchecked Sendable {
    public let marker: Int64
    private let source: CGEventSource?

    public init(marker: Int64 = Int64.random(in: 1...Int64.max)) {
        self.marker = marker == 0 ? 1 : marker
        source = CGEventSource(stateID: .privateState)
        source?.userData = self.marker
        source?.localEventsSuppressionInterval = 0

        let permitAllLocalEvents = CGEventFilterMask(rawValue: 0x7)
        source?.setLocalEventsFilterDuringSuppressionState(
            permitAllLocalEvents,
            state: .eventSuppressionStateSuppressionInterval
        )
        source?.setLocalEventsFilterDuringSuppressionState(
            permitAllLocalEvents,
            state: .eventSuppressionStateRemoteMouseDrag
        )
    }

    public var isHealthy: Bool {
        source != nil
    }

    public func currentCursorLocation() -> Point2D? {
        guard let point = CGEvent(source: nil)?.location,
              point.x.isFinite, point.y.isFinite else { return nil }
        return Point2D(x: point.x, y: point.y)
    }

    public func activeDisplays() -> [InputDisplay] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &identifiers, &count) == .success else { return [] }
        return identifiers.prefix(Int(count)).compactMap { identifier in
            let bounds = CGDisplayBounds(identifier)
            let display = InputDisplay(
                id: identifier,
                minX: bounds.minX,
                minY: bounds.minY,
                maxX: bounds.maxX,
                maxY: bounds.maxY
            )
            return display.isDrawable ? display : nil
        }
    }

    public func isPhysicalButtonPressed(_ button: InputMouseButton) -> Bool {
        CGEventSource.buttonState(.hidSystemState, button: button.cgButton)
    }

    public func physicalModifierFlags() -> InputModifierFlags {
        let flags = CGEventSource.flagsState(.hidSystemState)
        var result: InputModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
    }

    public func post(_ events: [LowLevelInputEvent]) -> Bool {
        guard let constructed = constructEvents(events) else { return false }
        constructed.forEach { $0.post(tap: .cghidEventTap) }
        return true
    }

    /// Constructs a complete batch without posting it. Keeping construction in
    /// one path lets tests verify the real private-source modifier policy while
    /// preserving the all-or-nothing posting contract.
    func constructEvents(_ events: [LowLevelInputEvent]) -> [CGEvent]? {
        guard let source, !events.isEmpty else { return nil }
        var constructed: [CGEvent] = []
        constructed.reserveCapacity(events.count)
        for event in events {
            guard let cgEvent = makeEvent(event, source: source) else { return nil }
            cgEvent.setIntegerValueField(.eventSourceUserData, value: marker)
            constructed.append(cgEvent)
        }
        return constructed
    }

    public func isGeneratedEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    private func makeEvent(_ event: LowLevelInputEvent, source: CGEventSource) -> CGEvent? {
        let result: CGEvent
        switch event {
        case let .mouse(kind, position, button, clickState):
            guard let mouseEvent = CGEvent(
                mouseEventSource: source,
                mouseType: kind.cgEventType,
                mouseCursorPosition: CGPoint(x: position.x, y: position.y),
                mouseButton: button.cgButton
            ) else { return nil }
            mouseEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
            result = mouseEvent

        case let .scroll(dx, dy):
            guard let scrollEvent = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: dy,
                wheel2: dx,
                wheel3: 0
            ) else { return nil }
            result = scrollEvent

        case let .key(keyCode, isDown, _):
            guard let keyEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: isDown
            ) else { return nil }
            keyEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            result = keyEvent
        }
        Self.applyModifierPolicy(to: result, for: event)
        return result
    }

    /// Applies the complete modifier policy after Core Graphics has created
    /// the event. Mouse and scroll events are semantic unmodified input and
    /// must never inherit Command from this backend's private zoom source.
    /// Keyboard shortcuts retain only their explicitly requested flags.
    static func applyModifierPolicy(to event: CGEvent, for input: LowLevelInputEvent) {
        switch input {
        case .mouse, .scroll:
            event.flags = []
        case let .key(_, _, modifiers):
            event.flags = modifiers.cgFlags
        }
    }
}

private extension InputMouseButton {
    var cgButton: CGMouseButton {
        switch self {
        case .left: .left
        case .right: .right
        case .other: .center
        }
    }
}

private extension InputMouseEventKind {
    var cgEventType: CGEventType {
        switch self {
        case .moved: .mouseMoved
        case .leftDown: .leftMouseDown
        case .leftUp: .leftMouseUp
        case .leftDragged: .leftMouseDragged
        case .rightDown: .rightMouseDown
        case .rightUp: .rightMouseUp
        case .otherDown: .otherMouseDown
        case .otherUp: .otherMouseUp
        case .otherDragged: .otherMouseDragged
        }
    }
}

private extension InputModifierFlags {
    var cgFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.command) { result.insert(.maskCommand) }
        if contains(.shift) { result.insert(.maskShift) }
        if contains(.option) { result.insert(.maskAlternate) }
        if contains(.control) { result.insert(.maskControl) }
        return result
    }
}
