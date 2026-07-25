import Foundation

public enum PauseReason: String, Codable, Equatable, Sendable {
    case startup
    case user
    case emergency
    case trackingLoss
    case permission
    case sleep
    case error
}

/// Synchronous output gate. It always begins closed and never re-enables itself.
public final class SafetyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _isPaused = true
    private var _reason: PauseReason = .startup
    private var _generation: UInt64 = 0
    private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    public var isPaused: Bool { lock.withLock { _isPaused } }
    public var reason: PauseReason { lock.withLock { _reason } }
    public var generation: UInt64 { lock.withLock { _generation } }

    public func enableExplicitly() {
        lock.withLock {
            _isPaused = false
            _reason = .user
            _generation &+= 1
        }
    }

    public func pause(_ reason: PauseReason) {
        let handlers: [@Sendable () -> Void] = lock.withLock {
            _isPaused = true
            _reason = reason
            _generation &+= 1
            return Array(cancellationHandlers.values)
        }
        handlers.forEach { $0() }
    }

    public func emergencyPause() {
        pause(.emergency)
    }

    @discardableResult
    public func onPause(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.withLock { cancellationHandlers[id] = handler }
        return id
    }

    public func removeHandler(_ id: UUID) {
        _ = lock.withLock { cancellationHandlers.removeValue(forKey: id) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
