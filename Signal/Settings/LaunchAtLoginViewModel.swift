import Combine
import Foundation

@MainActor
public final class LaunchAtLoginViewModel: ObservableObject {
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var requiresApproval: Bool

    private let controller: LaunchAtLoginControlling

    public init(controller: LaunchAtLoginControlling) {
        self.controller = controller
        isEnabled = controller.isEnabled
        requiresApproval = controller.requiresApproval
    }

    public func refresh() {
        let nextIsEnabled = controller.isEnabled
        let nextRequiresApproval = controller.requiresApproval
        if isEnabled != nextIsEnabled {
            isEnabled = nextIsEnabled
        }
        if requiresApproval != nextRequiresApproval {
            requiresApproval = nextRequiresApproval
        }
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            try controller.setEnabled(enabled)
            isEnabled = controller.isEnabled
            requiresApproval = controller.requiresApproval
            errorMessage = nil
        } catch {
            isEnabled = controller.isEnabled
            requiresApproval = controller.requiresApproval
            errorMessage = error.localizedDescription
        }
    }

    public func openLoginItemsSettings() {
        controller.openLoginItemsSettings()
    }
}
