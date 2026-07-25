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

    /// Runs a synchronous output operation only while the gate is open.
    ///
    /// The gate lock remains held for the operation, so a concurrent pause waits
    /// for the operation to finish and no operation can begin after pause returns.
    /// The body must not call back into `SafetyGate`.
    @discardableResult
    public func performIfEnabled<T>(_ body: () throws -> T) rethrows -> T? {
        try lock.withLock {
            guard !_isPaused else { return nil }
            return try body()
        }
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
