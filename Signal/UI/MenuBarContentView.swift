import SwiftUI

public struct MenuBarContentView: View {
    @ObservedObject private var model: SignalUIModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var launchAtLogin: LaunchAtLoginViewModel
    private let actions: SignalUIActions

    @State private var confirmingReset = false

    public init(
        model: SignalUIModel,
        settings: SettingsStore,
        launchAtLogin: LaunchAtLoginViewModel,
        actions: SignalUIActions
    ) {
        self.model = model
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.statusText, systemImage: model.statusSymbol)
                .font(.headline)
                .foregroundStyle(model.statusIsWarning ? .orange : .primary)

            Button("Open Signal…", action: actions.openMainWindow)

            Divider()

            Picker(
                "Mode",
                selection: Binding(
                    get: { model.mode },
                    set: { actions.setMode($0) }
                )
            ) {
                ForEach(SignalMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if !model.cameraAuthorized || !model.accessibilityTrusted {
                permissionButtons
            }

            Text("Camera frames and hand landmarks are processed only on this Mac. Signal does not record or transmit video.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Practice & Gesture Guide…", action: actions.openCalibration)
            Text("Practice the index-only pointer and one-hand thumb–index pinch: release to click, move up/down to scroll, or move right/left to zoom. Practice stays input-blocked until both permissions are granted and you explicitly choose Control.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings…", action: actions.openSettings)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            if launchAtLogin.requiresApproval {
                Text("macOS requires approval in Login Items before Signal can launch automatically.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Open Login Items Settings") {
                    launchAtLogin.openLoginItemsSettings()
                }
            } else if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Open Login Items Settings") {
                    launchAtLogin.openLoginItemsSettings()
                }
            }

            Button("Reset Safe Defaults…", role: .destructive) {
                confirmingReset = true
            }

            Divider()

            Button("Emergency Stop  ⌃⌥⌘H", role: .destructive, action: actions.emergencyStop)
            Button("Quit Signal", action: actions.quit)
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
        .confirmationDialog(
            "Restore all gesture tuning and application zoom profiles?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restore Safe Defaults", role: .destructive) {
                settings.resetSafeDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var permissionButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.cameraAuthorized {
                switch model.cameraPermission {
                case .denied:
                    Text("Camera access is denied. Open System Settings › Privacy & Security › Camera and enable Signal.")
                        .font(.caption)
                case .restricted:
                    Text("Camera access is restricted by macOS or device policy. Contact the device administrator.")
                        .font(.caption)
                case .notDetermined, .unknown, .authorized:
                    Button("Grant Camera Access…", action: actions.requestCameraPermission)
                }
            }
            if !model.accessibilityTrusted {
                Button("Grant Accessibility Access…", action: actions.requestAccessibilityPermission)
            }
        }
    }
}
