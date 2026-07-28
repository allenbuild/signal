import QuartzCore
import SwiftUI

@MainActor
public struct CalibrationView: View {
    public var previewLayer: CALayer?
    @ObservedObject private var viewModel: CalibrationViewModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var uiModel: SignalUIModel
    private let actions: SignalUIActions

    @State private var selection: LandmarkSelection?
    @State private var confirmingReset = false
    @State private var gestureGuideExpanded = true

    public init(
        previewLayer: CALayer?,
        viewModel: CalibrationViewModel,
        settings: SettingsStore,
        uiModel: SignalUIModel,
        actions: SignalUIActions
    ) {
        self.previewLayer = previewLayer
        self.viewModel = viewModel
        self.settings = settings
        self.uiModel = uiModel
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 0) {
            previewPanel
                .frame(minWidth: 640, idealWidth: 820, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            diagnosticsPanel
                .frame(width: 360)
                .background(.regularMaterial)
        }
        .frame(minWidth: 1_000, minHeight: 680)
        .onDisappear {
            actions.closeCalibration()
            viewModel.clear()
        }
        .confirmationDialog(
            "Restore all gesture tuning and disable screen zoom?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restore Safe Defaults", role: .destructive) {
                settings.resetSafeDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var previewPanel: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            MirroredPreviewHost(previewLayer: previewLayer)
            LandmarkOverlayView(snapshot: viewModel.overlay, selection: $selection)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusChip(uiModel.statusText, symbol: uiModel.statusSymbol, warning: uiModel.statusIsWarning)
                    statusChip(
                        viewModel.diagnostics.inputEnabled ? "Input enabled" : "Calibration only — input blocked",
                        symbol: viewModel.diagnostics.inputEnabled ? "cursorarrow.motionlines" : "lock.shield",
                        warning: false
                    )
                }
                HStack(spacing: 12) {
                    legend(color: .white, text: "Raw", hollow: true)
                    legend(color: .cyan, text: "Filtered", hollow: false)
                    Text("Click a filtered point for confidence and coordinates")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(12)

            if viewModel.overlay?.hands.isEmpty != false {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.slash")
                        .font(.largeTitle)
                    Text("No hand detected")
                        .font(.headline)
                    Text("Keep your hand in frame with the wrist and fingertips visible.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
            }
        }
        .clipped()
    }

    private var diagnosticsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calibration & Diagnostics")
                    .font(.title2.bold())

                if uiModel.status == .cameraUnavailable, uiModel.cameraAuthorized {
                    diagnosticSection("Camera recovery") {
                        Text("Capture stopped or was interrupted. Control remains blocked while you retry calibration.")
                            .font(.caption)
                        Button("Retry Camera", action: actions.retryCamera)
                    }
                }

                diagnosticSection("Permissions") {
                    permissionLine("Camera", granted: uiModel.cameraAuthorized)
                    permissionLine("Accessibility", granted: uiModel.accessibilityTrusted)
                    if !uiModel.cameraAuthorized {
                        switch uiModel.cameraPermission {
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
                    if !uiModel.accessibilityTrusted {
                        Button("Grant Accessibility Access…", action: actions.requestAccessibilityPermission)
                    }
                }

                gestureGuideSection

                diagnosticSection("Tracking") {
                    valueLine("Quality", viewModel.diagnostics.trackingQuality.rawValue)
                    valueLine(
                        "Degradation reason",
                        degradationReasonText(viewModel.diagnostics.gesture.degradationReason)
                    )
                    valueLine("Capture FPS", number(viewModel.diagnostics.tracking.captureFPS, digits: 1))
                    valueLine("Processed FPS", number(viewModel.diagnostics.tracking.processedFPS, digits: 1))
                    valueLine("Dropped frames (current-run total)", "\(viewModel.diagnostics.tracking.droppedFrames)")
                    valueLine("Vision latency", number(viewModel.diagnostics.tracking.visionLatencyMilliseconds, digits: 1) + " ms")
                    valueLine("End-to-end latency", number(viewModel.diagnostics.tracking.endToEndLatencyMilliseconds, digits: 1) + " ms")
                }

                diagnosticSection("Gesture & input") {
                    valueLine(
                        "Recognized pose",
                        viewModel.diagnostics.gesture.recognizedPose?.rawValue ?? "—"
                    )
                    valueLine("Active gesture", activeGestureText(viewModel.diagnostics.gesture.activeGesture))
                    valueLine(
                        "Middle-thumb normalized distance",
                        optionalNumber(viewModel.diagnostics.gesture.middleThumbNormalizedDistance)
                    )
                    valueLine("Pending click", viewModel.diagnostics.gesture.pendingClick ? "yes" : "no")
                    valueLine(
                        "Scrolling active",
                        viewModel.diagnostics.gesture.activeGesture == .scroll ? "yes" : "no"
                    )
                    valueLine(
                        "Pointer suppressed",
                        viewModel.diagnostics.gesture.pointerSuppressionReason?.rawValue ?? "none"
                    )
                    valueLine(
                        "Pinch duration",
                        optionalSeconds(viewModel.diagnostics.gesture.pinchDuration)
                    )
                    valueLine(
                        "Required-joint confidence",
                        optionalNumber(viewModel.diagnostics.gesture.requiredJointConfidence)
                    )
                    valueLine(
                        "Vertical scroll displacement",
                        optionalNumber(viewModel.diagnostics.gesture.scrollDisplacement)
                    )
                    valueLine(
                        "Scroll anchor",
                        pointText(viewModel.diagnostics.gesture.scrollAnchor)
                    )
                    valueLine(
                        "Raw vertical scroll Δ",
                        optionalNumber(viewModel.diagnostics.gesture.scrollVerticalDelta)
                    )
                    valueLine(
                        "Vertical scroll Δ",
                        optionalNumber(viewModel.diagnostics.gesture.scrollDelta)
                    )
                    valueLine(
                        "Fist rejection",
                        viewModel.diagnostics.gesture.fistRejectionReason?.rawValue ?? "none"
                    )
                    valueLine(
                        "Horizontal zoom displacement",
                        optionalNumber(viewModel.diagnostics.gesture.zoomDistance)
                    )
                    valueLine(
                        "Horizontal zoom Δ",
                        optionalNumber(viewModel.diagnostics.gesture.zoomDelta)
                    )
                    valueLine("Input", viewModel.diagnostics.inputEnabled ? "enabled" : "blocked")
                    valueLine("Pointer Δ", pointText(viewModel.diagnostics.input.pointerDelta))
                    valueLine("Engine state", viewModel.diagnostics.gestureState)
                }

                ForEach(viewModel.overlay?.hands ?? [], id: \.hand.id) { overlay in
                    handSection(overlay)
                }

                if let selection, let detail = selectedDetail(selection) {
                    diagnosticSection("Selected landmark") {
                        valueLine("Hand", "\(selection.handID.rawValue)")
                        valueLine("Joint", landmarkLabel(selection.landmark))
                        valueLine("Raw", pointText(detail.raw?.position))
                        valueLine("Raw confidence", optionalNumber(detail.raw?.confidence))
                        valueLine("Filtered", pointText(detail.filtered?.position))
                        valueLine("Filtered confidence", optionalNumber(detail.filtered?.confidence))
                    }
                }

                liveTuningSection

                Button("Emergency Stop  ⌃⌥⌘H", role: .destructive, action: actions.emergencyStop)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private var gestureGuideSection: some View {
        DisclosureGroup(isExpanded: $gestureGuideExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                Text("This window is for practice. If it closes, reopen it from the Signal menu-bar hand. Control stays blocked until both permissions are granted and you choose Enable Control from that menu.")
                    .foregroundStyle(.secondary)
                gestureGuideLine("Index finger only", "Move the pointer")
                gestureGuideLine("Quick thumb–middle pinch", "Release to left-click once; the pointer stays frozen")
                gestureGuideLine("Hold thumb–middle pinch and keep moving vertically", "Up scrolls up; down scrolls down. Stop moving to stop scrolling")
                gestureGuideLine("Hold thumb–middle pinch and keep moving horizontally", "Right zooms in; left zooms out. Stop moving to stop zooming")
            }
            .padding(.top, 7)
        } label: {
            Label("Gesture guide", systemImage: "hand.raised")
                .font(.headline)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func gestureGuideLine(_ gesture: String, _ action: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(gesture).fontWeight(.semibold)
            Text(action).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func activeGestureText(_ gesture: ActiveGestureDiagnostic) -> String {
        switch gesture {
        case .rest: "rest"
        case .pointer: "pointer"
        case .pendingClick: "pending click"
        case .scroll: "vertical scroll"
        case .zoom: "horizontal pinch zoom"
        }
    }

    private func degradationReasonText(_ reason: TrackingDegradationReason?) -> String {
        guard let reason else { return "none" }
        return switch reason {
        case .staleFrame: "stale frame"
        case .noHandDetected: "no hand detected"
        case .palmAnchorsMissing: "palm anchors missing"
        case .invalidPalmScale: "invalid palm scale"
        case .associationAmbiguous: "hand association ambiguous"
        case .handIdentityLost: "hand ID lost"
        case .lowRequiredJointConfidence: "low required-joint confidence"
        case .poseAmbiguity: "pose ambiguity"
        case .invalidTimestamp: "invalid timestamp"
        case .visionFailure: "Vision request failed"
        }
    }

    @ViewBuilder
    private func handSection(_ overlay: CalibrationHandOverlay) -> some View {
        diagnosticSection("Hand \(overlay.hand.id.rawValue)") {
            valueLine("Pose", overlay.pose?.metrics.pose.rawValue ?? "unknown")
            valueLine("Confidence", number(overlay.hand.confidence, digits: 3))
            valueLine("Association", overlay.hand.associationCertain ? "certain" : "ambiguous")
            valueLine("Palm width", number(overlay.hand.palmWidth, digits: 4))
            valueLine("Palm scale", overlay.hand.palmScaleSource.rawValue)
            valueLine("Velocity", pointText(overlay.hand.velocity))
            valueLine("Missing duration", number(overlay.hand.missingDuration, digits: 3) + " s")
            valueLine("Middle-thumb distance", optionalNumber(pinchDistance(overlay.hand.filteredLandmarks)))
            valueLine("Middle-thumb normalized distance", optionalNumber(overlay.pose?.metrics.pinchRatio))
            valueLine(
                "Pinch thresholds",
                "close \(number(settings.tuning.pinchCloseRatio, digits: 2)) / open \(number(settings.tuning.pinchOpenRatio, digits: 2))"
            )
        }
    }

    private var liveTuningSection: some View {
        diagnosticSection("Live tuning") {
            compactSlider("Pointer sensitivity", value: doubleBinding(\.pointerSensitivity), range: 100...1_200, step: 10)
            compactSlider("Pointer dead zone", value: doubleBinding(\.pointerDeadZone), range: 0...0.08, step: 0.001)
            compactSlider("Required-joint confidence", value: doubleBinding(\.minimumLandmarkConfidence), range: 0.1...1, step: 0.01)
            compactSlider(
                "Middle-thumb close",
                value: doubleBinding(\.pinchCloseRatio),
                range: 0...max(0.01, settings.tuning.pinchOpenRatio - 0.01),
                step: 0.01
            )
            compactSlider(
                "Middle-thumb open",
                value: doubleBinding(\.pinchOpenRatio),
                range: min(0.99, settings.tuning.pinchCloseRatio + 0.01)...settings.tuning.pinchIntentRatio,
                step: 0.01
            )
            compactSlider(
                "Pointer-freeze intent",
                value: doubleBinding(\.pinchIntentRatio),
                range: settings.tuning.pinchOpenRatio...1,
                step: 0.01
            )
            compactSlider(
                "Click maximum duration",
                value: doubleBinding(\.quickPinchMaximumDuration),
                range: 0.05...0.60,
                step: 0.01
            )
            compactSlider(
                "Scroll activation",
                value: doubleBinding(\.pinchScrollActivationDisplacement),
                range: 0.01...0.30,
                step: 0.005
            )
            Stepper(
                "Scroll stabilization frames: \(settings.tuning.scrollStabilizationFrames)",
                value: intBinding(\.scrollStabilizationFrames),
                in: 0...6
            )
            compactSlider("Vertical scroll sensitivity", value: doubleBinding(\.scrollSensitivityY), range: 10...400, step: 5)
            compactSlider("One Euro beta", value: doubleBinding(\.oneEuroBeta), range: 0...2, step: 0.05)
            compactSlider("Zoom sensitivity", value: doubleBinding(\.zoomSensitivity), range: 0.1...5, step: 0.1)
            Button("Restore Safe Defaults…", role: .destructive) {
                confirmingReset = true
            }
        }
    }

    private func diagnosticSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func valueLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func permissionLine(_ title: String, granted: Bool) -> some View {
        Label(granted ? "\(title): granted" : "\(title): required", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? .green : .orange)
            .font(.caption)
    }

    private func statusChip(_ text: String, symbol: String, warning: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(warning ? .orange : .white)
            .background(.black.opacity(0.7), in: Capsule())
    }

    private func legend(color: Color, text: String, hollow: Bool) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(color, lineWidth: 1.5)
                if !hollow {
                    Circle().fill(color).padding(1)
                }
            }
            .frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.white)
        }
    }

    private func compactSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(number(value.wrappedValue, digits: 3))
                    .font(.caption.monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<GestureTuning, Double>) -> Binding<Double> {
        Binding(
            get: { settings.tuning[keyPath: keyPath] },
            set: { value in settings.updateTuning { $0[keyPath: keyPath] = value } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<GestureTuning, Int>) -> Binding<Int> {
        Binding(
            get: { settings.tuning[keyPath: keyPath] },
            set: { value in settings.updateTuning { $0[keyPath: keyPath] = value } }
        )
    }

    private func selectedDetail(_ selection: LandmarkSelection) -> (raw: LandmarkSample?, filtered: LandmarkSample?)? {
        guard let hand = viewModel.overlay?.hands.first(where: { $0.hand.id == selection.handID })?.hand else {
            return nil
        }
        return (hand.rawLandmarks[selection.landmark], hand.filteredLandmarks[selection.landmark])
    }

    private func pinchDistance(_ landmarks: HandLandmarks) -> Double? {
        guard let thumb = landmarks[.thumbTip]?.position,
              let middle = landmarks[.middleTip]?.position else {
            return nil
        }
        return hypot(middle.x - thumb.x, middle.y - thumb.y)
    }

    private func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    private func optionalNumber(_ value: Double?) -> String {
        value.map { number($0, digits: 4) } ?? "—"
    }

    private func optionalSeconds(_ value: TimeInterval?) -> String {
        value.map { number($0, digits: 3) + " s" } ?? "—"
    }

    private func pointText(_ point: Point2D?) -> String {
        guard let point else { return "—" }
        return "(\(number(point.x, digits: 3)), \(number(point.y, digits: 3)))"
    }

    private func landmarkLabel(_ landmark: LandmarkName) -> String {
        String(describing: landmark)
    }
}
