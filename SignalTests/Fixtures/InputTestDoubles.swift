import Foundation
@testable import Signal

final class FakeInputBackend: InputEventBackend, @unchecked Sendable {
    let marker: Int64

    private let lock = NSLock()
    private var storedEvents: [LowLevelInputEvent] = []
    private var storedBatches: [[LowLevelInputEvent]] = []
    private var storedCursor: Point2D? = Point2D(x: 100, y: 100)
    private var storedDisplays = [InputDisplay(id: 1, minX: 0, minY: 0, maxX: 1_000, maxY: 800)]
    private var storedPhysicalButtons: Set<InputMouseButton> = []
    private var storedModifiers: InputModifierFlags = []
    private var storedHealthy = true
    private var storedPostResult = true

    init(marker: Int64 = 0x48414E4450494C54) {
        self.marker = marker
    }

    var isHealthy: Bool { withLock { storedHealthy } }

    func currentCursorLocation() -> Point2D? { withLock { storedCursor } }
    func activeDisplays() -> [InputDisplay] { withLock { storedDisplays } }
    func isPhysicalButtonPressed(_ button: InputMouseButton) -> Bool {
        withLock { storedPhysicalButtons.contains(button) }
    }
    func physicalModifierFlags() -> InputModifierFlags { withLock { storedModifiers } }

    func post(_ events: [LowLevelInputEvent]) -> Bool {
        withLock {
            guard storedPostResult else { return false }
            storedBatches.append(events)
            storedEvents.append(contentsOf: events)
            return true
        }
    }

    func configure(
        cursor: Point2D? = nil,
        displays: [InputDisplay]? = nil,
        physicalButtons: Set<InputMouseButton>? = nil,
        modifiers: InputModifierFlags? = nil,
        healthy: Bool? = nil,
        postResult: Bool? = nil
    ) {
        withLock {
            if let cursor { storedCursor = cursor }
            if let displays { storedDisplays = displays }
            if let physicalButtons { storedPhysicalButtons = physicalButtons }
            if let modifiers { storedModifiers = modifiers }
            if let healthy { storedHealthy = healthy }
            if let postResult { storedPostResult = postResult }
        }
    }

    func events() -> [LowLevelInputEvent] { withLock { storedEvents } }
    func batches() -> [[LowLevelInputEvent]] { withLock { storedBatches } }
    func setCursorResult(_ cursor: Point2D?) { withLock { storedCursor = cursor } }
    func clearEvents() {
        withLock {
            storedEvents.removeAll()
            storedBatches.removeAll()
        }
    }

    @discardableResult
    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class FakeInputTrustProvider: InputTrustProviding, @unchecked Sendable {
    var isAccessibilityTrusted: Bool
    var canPostEvents: Bool

    init(trusted: Bool = true, canPost: Bool = true) {
        isAccessibilityTrusted = trusted
        canPostEvents = canPost
    }
}

final class FakeFrontmostApplicationProvider:
    FrontmostApplicationProviding, @unchecked Sendable {
    var frontmostBundleIdentifier: String?

    init(_ bundleIdentifier: String? = "com.apple.Safari") {
        frontmostBundleIdentifier = bundleIdentifier
    }
}

final class FakeInputClock: InputMonotonicClock, @unchecked Sendable {
    var now: TimeInterval

    init(now: TimeInterval = 0) {
        self.now = now
    }
}
