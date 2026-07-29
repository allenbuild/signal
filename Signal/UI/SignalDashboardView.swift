import SwiftUI

@MainActor
public struct SignalDashboardView: View {
    private let presentation: SignalDashboardPresentation
    private let actions: SignalDashboardActions
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 150), spacing: 12),
        count: 4
    )

    public init(
        presentation: SignalDashboardPresentation,
        actions: SignalDashboardActions
    ) {
        self.presentation = presentation
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                commandGrid
                detailGrid
            }
            .padding(24)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 14) {
            Text("signal")
                .font(.system(size: 42, weight: .regular, design: .serif))
                .accessibilityAddTraits(.isHeader)

            Picker(
                "Signal mode",
                selection: Binding(
                    get: { presentation.mode },
                    set: { mode in
                        actions.selectMode(mode)
                    }
                )
            ) {
                ForEach(SignalDashboardMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            HStack(spacing: 10) {
                statusBadge
                telemetryBadge(
                    symbol: "camera.fill",
                    text: presentation.telemetry.cameraState
                )
                telemetryBadge(
                    symbol: "hand.raised.fill",
                    text: presentation.telemetry.recognizedPose
                )
                telemetryBadge(
                    symbol: "waveform.path.ecg",
                    text: "\(Int(presentation.telemetry.confidence * 100))%"
                )
            }

            if !presentation.status.detail.isEmpty {
                Text(presentation.status.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var statusBadge: some View {
        Label(
            presentation.status.title,
            systemImage: statusSymbol
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private func telemetryBadge(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }

    private var commandGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(presentation.cards) { card in
                SignalDashboardCardView(
                    card: card,
                    activationProgress: presentation.activeCardID == card.id
                        ? presentation.activationProgress
                        : 0,
                    edit: { actions.editCommand(card.id) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gesture commands")
    }

    private var detailGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            permissionPanel
            telemetryPanel
            activityPanel
        }
    }

    private var permissionPanel: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                if presentation.permissions.isEmpty {
                    Text("Permission status unavailable")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.permissions) { permission in
                        permissionRow(permission)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func permissionRow(
        _ permission: SignalDashboardPermission
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: permissionSymbol(permission.state))
                .foregroundStyle(permissionColor(permission.state))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(permission.kind.title)
                    if !permission.kind.isCorePermission {
                        Text("Optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(permission.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !permission.detail.isEmpty {
                    Text(permission.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if permission.state.needsUserAction {
                Button("Review") {
                    actions.requestPermission(permission.kind)
                }
                .controlSize(.small)
            }
        }
    }

    private var telemetryPanel: some View {
        GroupBox("Live telemetry") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                metricRow("Tracking", presentation.telemetry.trackingQuality)
                metricRow(
                    "Capture / processed",
                    "\(format(presentation.telemetry.captureFPS)) / " +
                        "\(format(presentation.telemetry.processedFPS)) FPS"
                )
                metricRow(
                    "Vision / end-to-end",
                    "\(format(presentation.telemetry.visionLatencyMilliseconds)) / " +
                        "\(format(presentation.telemetry.endToEndLatencyMilliseconds)) ms"
                )
                metricRow(
                    "Transaction",
                    presentation.telemetry.controlTransaction
                )
                metricRow("Application", presentation.telemetry.activeApplication)
                metricRow("Zoom profile", presentation.telemetry.activeZoomProfile)
                metricRow("Last command", presentation.lastCommand)
                metricRow("Result", presentation.lastCommandResult)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
        }
        .font(.caption)
    }

    private var activityPanel: some View {
        GroupBox("Activity") {
            VStack(alignment: .leading, spacing: 8) {
                if presentation.activity.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.activity.prefix(8)) { entry in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: activitySymbol(entry.outcome))
                                .foregroundStyle(activityColor(entry.outcome))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.title)
                                        .font(.caption.weight(.medium))
                                    Spacer(minLength: 4)
                                    Text(
                                        entry.timestamp,
                                        format: .dateTime
                                            .hour()
                                            .minute()
                                            .second()
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                Divider()
                HStack {
                    Button("Calibration", action: actions.openCalibration)
                    Button("Settings", action: actions.openSettings)
                    Spacer()
                    Button(
                        "Emergency Stop  ⌃⌥⌘H",
                        role: .destructive,
                        action: actions.emergencyStop
                    )
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusSymbol: String {
        switch presentation.status.kind {
        case .paused: "pause.circle.fill"
        case .ready: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch presentation.status.kind {
        case .paused: .secondary
        case .ready: .green
        case .attention: .orange
        case .error: .red
        }
    }

    private func permissionSymbol(
        _ state: SignalDashboardPermissionState
    ) -> String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .optional, .notRequired: "minus.circle"
        case .notDetermined: "questionmark.circle"
        case .denied, .restricted, .requiresRelaunch:
            "exclamationmark.triangle.fill"
        }
    }

    private func permissionColor(
        _ state: SignalDashboardPermissionState
    ) -> Color {
        switch state {
        case .granted: .green
        case .optional, .notRequired, .notDetermined: .secondary
        case .denied, .restricted, .requiresRelaunch: .orange
        }
    }

    private func activitySymbol(
        _ outcome: SignalDashboardActivityOutcome
    ) -> String {
        switch outcome {
        case .information: "info.circle"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    private func activityColor(
        _ outcome: SignalDashboardActivityOutcome
    ) -> Color {
        switch outcome {
        case .information: .secondary
        case .success: .green
        case .failure: .red
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

@MainActor
private struct SignalDashboardCardView: View {
    let card: SignalDashboardCommandCard
    let activationProgress: Double
    let edit: @MainActor () -> Void

    var body: some View {
        Group {
            if card.id == .fist {
                Button(action: edit) {
                    content
                }
                .buttonStyle(.plain)
                .disabled(!card.isEnabled)
                .accessibilityHint(
                    "Opens the local Fist command editor. Does not execute the command."
                )
            } else {
                content
                    .accessibilityHint("A fixed reviewed command.")
            }
        }
        .accessibilityLabel("\(card.gestureLabel), \(card.commandName)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: card.symbolName)
                    .font(.title2)
                Spacer()
                if activationProgress > 0 {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: activationProgress)
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Activation progress")
                    .accessibilityValue(
                        "\(Int(activationProgress * 100)) percent"
                    )
                }
            }

            Text(card.gestureLabel)
                .font(.headline)
            Text(card.commandName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(card.id == .fist
                 ? (card.isConfigured ? "Edit command" : "Set up command")
                 : "Fixed reviewed command")
                .font(.caption)
                .foregroundStyle(card.id == .fist ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
        .opacity(card.isEnabled ? 1 : 0.55)
    }
}
