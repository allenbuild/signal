import AppKit
import SwiftUI

@MainActor
public struct SettingsView: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var launchAtLogin: LaunchAtLoginViewModel
    @State private var confirmingReset = false

    public init(store: SettingsStore, launchAtLogin: LaunchAtLoginViewModel) {
        self.store = store
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch Signal at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                Text("Control still starts disabled after every launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if launchAtLogin.requiresApproval {
                    Label(
                        "macOS approval is required in Login Items.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                } else if let message = launchAtLogin.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            }

            Section("Pointer") {
                tuningSlider("Sensitivity", value: doubleBinding(\.pointerSensitivity), range: 100...1_200, step: 10, suffix: " pt/palm")
                tuningSlider("Acceleration", value: doubleBinding(\.pointerAcceleration), range: 0...2, step: 0.05)
                tuningSlider("Dead zone", value: doubleBinding(\.pointerDeadZone), range: 0...0.08, step: 0.001, digits: 3)
                tuningSlider("Maximum delta", value: doubleBinding(\.pointerMaximumDelta), range: 10...200, step: 5, suffix: " pt")
            }

            Section("Smoothing") {
                tuningSlider("One Euro minimum cutoff", value: doubleBinding(\.oneEuroMinimumCutoff), range: 0.1...8, step: 0.1, suffix: " Hz")
                tuningSlider("One Euro derivative cutoff", value: doubleBinding(\.oneEuroDerivativeCutoff), range: 0.1...8, step: 0.1, suffix: " Hz")
                tuningSlider("One Euro beta", value: doubleBinding(\.oneEuroBeta), range: 0...2, step: 0.05)
            }

            Section("Tracking confidence") {
                tuningSlider("Required-joint confidence", value: doubleBinding(\.minimumLandmarkConfidence), range: 0.1...1, step: 0.01)
                tuningSlider("Pose stability", value: doubleBinding(\.poseStabilityDuration), range: 0...0.5, step: 0.01, suffix: " s")
                tuningSlider("Transient joint grace", value: doubleBinding(\.poseExitGraceDuration), range: 0...0.2, step: 0.01, suffix: " s")
            }

            Section("One-hand thumb–index pinch") {
                tuningSlider(
                    "Thumb–index close threshold",
                    value: doubleBinding(\.pinchCloseRatio),
                    range: 0...max(0.01, store.tuning.pinchOpenRatio - 0.01),
                    step: 0.01
                )
                tuningSlider(
                    "Thumb–index open threshold",
                    value: doubleBinding(\.pinchOpenRatio),
                    range: min(0.99, store.tuning.pinchCloseRatio + 0.01)...store.tuning.pinchIntentRatio,
                    step: 0.01
                )
                tuningSlider(
                    "Pointer-freeze intent threshold",
                    value: doubleBinding(\.pinchIntentRatio),
                    range: store.tuning.pinchOpenRatio...1,
                    step: 0.01
                )
                tuningSlider(
                    "Click maximum duration",
                    value: doubleBinding(\.quickPinchMaximumDuration),
                    range: 0.05...0.60,
                    step: 0.01,
                    suffix: " s"
                )
                tuningSlider(
                    "Scroll / zoom activation movement",
                    value: doubleBinding(\.pinchScrollActivationDisplacement),
                    range: 0.01...0.30,
                    step: 0.005,
                    suffix: " palm"
                )
                Stepper(
                    "Scroll stabilization frames: \(store.tuning.scrollStabilizationFrames)",
                    value: intBinding(\.scrollStabilizationFrames),
                    in: 0...6
                )
                tuningSlider("Vertical sensitivity", value: doubleBinding(\.scrollSensitivityY), range: 10...400, step: 5)
                tuningSlider("Acceleration", value: doubleBinding(\.scrollAcceleration), range: 0...2, step: 0.05)
            }

            Section("Horizontal pinch zoom") {
                tuningSlider("Sensitivity", value: doubleBinding(\.zoomSensitivity), range: 0.1...5, step: 0.1)
                tuningSlider("Step threshold", value: doubleBinding(\.zoomStepThreshold), range: 0.01...0.5, step: 0.01)
                Stepper(
                    "Maximum steps per frame: \(store.tuning.zoomMaximumStepsPerFrame)",
                    value: intBinding(\.zoomMaximumStepsPerFrame),
                    in: 1...8
                )
                Text("Horizontal movement sends app-aware zoom shortcuts to the frontmost application. Signal uses your saved app profile when one exists and Command +/− as the safe fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                LabeledContent("Emergency shortcut", value: "⌃⌥⌘H")
                Text("The emergency shortcut immediately blocks output and releases any input held by Signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restore Safe Defaults…", role: .destructive) {
                    confirmingReset = true
                }
            }

            if let message = store.lastValidationMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 620, idealHeight: 760)
        .confirmationDialog(
            "Restore all gesture tuning and application zoom profiles?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restore Safe Defaults", role: .destructive) {
                store.resetSafeDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<GestureTuning, Double>) -> Binding<Double> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in
                store.updateTuning { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<GestureTuning, Int>) -> Binding<Int> {
        Binding(
            get: { store.tuning[keyPath: keyPath] },
            set: { newValue in
                store.updateTuning { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func tuningSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String = "",
        digits: Int = 2
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(digits))) + suffix)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
