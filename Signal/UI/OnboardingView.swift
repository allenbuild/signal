import SwiftUI

public struct OnboardingView: View {
    @ObservedObject private var model: SignalUIModel
    private let actions: SignalUIActions

    public init(model: SignalUIModel, actions: SignalUIActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Set up Signal", systemImage: "hand.wave")
                .font(.title2.bold())

            Text("Camera frames are processed only on this Mac and are never recorded, retained, uploaded, or sent over a network.")
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Camera",
                explanation: "Needed to see hand landmarks. Access is requested only when you choose Grant Camera Access.",
                granted: model.cameraAuthorized,
                actionTitle: "Grant Camera Access",
                action: actions.requestCameraPermission
            )

            permissionRow(
                title: "Accessibility",
                explanation: "Needed only to post pointer, click, scroll, and zoom commands. If previously denied, reopen Privacy & Security in System Settings.",
                granted: model.accessibilityTrusted,
                actionTitle: "Open Accessibility Settings",
                action: actions.requestAccessibilityPermission
            )

            Divider()

            Label("Control always starts disabled after launch.", systemImage: "lock.shield")
                .font(.callout.weight(.medium))
            Text("You can open Calibration while output is disabled. Calibration must not post input unless you separately enable Control.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Calibration", action: actions.openCalibration)
                Spacer()
                Button("Enable Control", action: actions.enableControl)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.cameraAuthorized || !model.accessibilityTrusted)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 560)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        explanation: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline)
                    Text(granted ? "Granted" : "Required")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(granted ? .green : .orange)
                }
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !granted {
                    Button(actionTitle, action: action)
                }
            }
        }
    }
}
