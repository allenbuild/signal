import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: String, Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

/// Thin, status-authoritative wrapper around `SMAppService.mainApp`.
public final class LaunchAtLoginController: LaunchAtLoginControlling, @unchecked Sendable {
    public var onChange: (@Sendable (LaunchAtLoginStatus) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return changeCallback
        }
        set {
            lock.lock()
            changeCallback = newValue
            lock.unlock()
        }
    }

    public var isEnabled: Bool {
        service.status == .enabled
    }

    public var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    private let service: SMAppService
    private let lock = NSLock()
    private var changeCallback: (@Sendable (LaunchAtLoginStatus) -> Void)?
    private var lastStatus: LaunchAtLoginStatus?

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    @discardableResult
    public func refresh() -> LaunchAtLoginStatus {
        let status = Self.map(service.status)

        lock.lock()
        let changed = status != lastStatus
        lastStatus = status
        let callback = changeCallback
        lock.unlock()

        if changed {
            callback?(status)
        }
        return status
    }

    public func setEnabled(_ enabled: Bool) throws {
        defer { _ = refresh() }

        if enabled {
            guard service.status != .enabled,
                  service.status != .requiresApproval else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered,
                  service.status != .notFound else {
                return
            }
            try service.unregister()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }
}
