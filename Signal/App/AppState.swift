import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var controlIntent: ControlIntent = .disabled
    @Published private(set) var status: AppStatus = .disabled
    @Published private(set) var calibrationIsOpen = false

    var statusText: String {
        switch status {
        case .disabled: "Control disabled"
        case .enabled: "Control enabled"
        case .paused: "Control paused"
        case .cameraPermissionMissing: "Camera permission required"
        case .accessibilityPermissionMissing: "Accessibility permission required"
        case .cameraUnavailable: "Camera unavailable"
        case .waitingForHand: "Control enabled — waiting for a clear hand"
        case .trackingDegraded: "Camera feed stalled — control stopped"
        case .emergencyStopped: "Emergency stop active"
        case let .error(message): "Error: \(message)"
        }
    }

    var statusSymbol: String {
        switch status {
        case .enabled: "hand.point.up.left.fill"
        case .waitingForHand: "hand.raised.fill"
        case .paused: "pause.circle"
        case .trackingDegraded: "hand.raised"
        case .cameraPermissionMissing, .accessibilityPermissionMissing,
             .cameraUnavailable, .emergencyStopped, .error:
            "exclamationmark.shield"
        case .disabled:
            "hand.raised.slash"
        }
    }

    func apply(controlIntent: ControlIntent, status: AppStatus) {
        self.controlIntent = controlIntent
        self.status = status
    }

    func setCalibrationOpen(_ isOpen: Bool) {
        calibrationIsOpen = isOpen
    }
}
