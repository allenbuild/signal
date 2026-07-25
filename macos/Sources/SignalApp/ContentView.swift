import SignalCore
import SwiftUI

struct SignalCommandCenter: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        NavigationSplitView {
            List(SignalSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("Signal")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.mode.displayName + " Mode", systemImage: "switch.2")
                        .font(.headline)
                    Text(model.isPaused ? "PAUSED" : "OUTPUT ENABLED")
                        .font(.caption.bold())
                        .foregroundStyle(model.isPaused ? .orange : .green)
                    Button(model.isPaused ? "Enable Output" : "Pause Output") {
                        model.toggleOutput()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        } detail: {
            Group {
                switch model.selectedSection {
                case .live: LiveView()
                case .gestures: GestureGridView()
                case .build: BuildCommandView()
                case .teach: TeachView()
                case .profiles: ProfilesView()
                case .settings: SignalSettingsView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .environmentObject(model)
            .toolbar {
                ToolbarItemGroup {
                    Picker("Mode", selection: Binding(get: { model.mode }, set: model.setMode)) {
                        ForEach(SignalMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    Button {
                        model.emergencyStop()
                    } label: {
                        Label("Emergency Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }
}

private struct LiveView: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                CameraCard()
                LiveGestureCard()
                MappingSummaryCard()
            }
            .padding()
            Divider()
            ReceiptList()
        }
        .navigationTitle("Live Command Center")
    }
}

private struct CameraCard: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mirrored Camera", systemImage: "camera")
                .font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.gradient)
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.mint)
                    Text(model.cameraStatus)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Vision landmarks • no frame upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            HStack {
                Button("Start Camera") { model.startCamera() }
                Button("Stop") { model.stopCamera() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LiveGestureCard: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Signal")
                .font(.headline)
            StatusPill(text: model.isPaused ? "PAUSED" : model.mode.displayName.uppercased(), color: model.isPaused ? .orange : .green)
            VStack(spacing: 8) {
                Image(systemName: model.candidate?.symbol ?? "hand.raised")
                    .font(.system(size: 58))
                Text(model.candidate?.displayName ?? "No command gesture")
                    .font(.title3.bold())
                ProgressView(value: model.holdProgress)
                Text("\(Int(model.confidence * 100))% confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            LabeledContent("Touch state", value: model.touchState.rawValue)
            LabeledContent("Next action", value: model.candidate.flatMap { model.mappedPlan(for: $0)?.name } ?? "—")
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MappingSummaryCard: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Command Palette").font(.headline)
                Spacer()
                Button("Edit") { model.selectedSection = .gestures }
            }
            ForEach(CommandGesture.allCases) { gesture in
                HStack {
                    Image(systemName: gesture.symbol).frame(width: 26)
                    Text(gesture.displayName)
                    Spacer()
                    Text(model.mappedPlan(for: gesture)?.name ?? "Unassigned")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReceiptList: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Receipts").font(.headline)
            if model.receipts.isEmpty {
                Text("Validated actions will leave local receipts here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.receipts.prefix(5)) { receipt in
                    HStack {
                        Image(systemName: receipt.status == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(receipt.status == .success ? .green : .orange)
                        Text(receipt.action.rawValue.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        Text(receipt.message).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

private struct GestureGridView: View {
    @EnvironmentObject private var model: SignalAppModel
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(CommandGesture.allCases) { gesture in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: gesture.symbol).font(.title)
                            Text(gesture.displayName).font(.headline)
                            Spacer()
                            Circle().fill(model.mappedPlan(for: gesture) == nil ? .gray : .green).frame(width: 9, height: 9)
                        }
                        Text(model.mappedPlan(for: gesture)?.name ?? "No command assigned")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Edit") {
                                model.selectedGesture = gesture
                                model.selectedSection = .build
                            }
                            Button("Test") {
                                model.selectedGesture = gesture
                                model.testSelectedGesture()
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .navigationTitle("Gesture Mappings")
    }
}

private struct BuildCommandView: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Describe a workflow").font(.title2.bold())
                Picker("Gesture", selection: $model.selectedGesture) {
                    ForEach(CommandGesture.allCases) { Text($0.displayName).tag($0) }
                }
                TextEditor(text: $model.prompt)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    model.buildPlan()
                } label: {
                    Label(model.isPlanning ? "Planning…" : "Create Validated Preview", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isPlanning)
                Text(model.plannerStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()

            VStack(alignment: .leading, spacing: 12) {
                Text("Review exact actions").font(.title2.bold())
                if let plan = model.previewPlan {
                    Text(plan.name).font(.headline)
                    Text(plan.description).foregroundStyle(.secondary)
                    List(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top) {
                            Text("\(index + 1)").font(.caption.bold())
                                .frame(width: 24, height: 24)
                                .background(.blue, in: Circle())
                                .foregroundStyle(.white)
                            VStack(alignment: .leading) {
                                Text(step.plainEnglish)
                                Text("Timeout \(step.timeoutMs) ms • \(step.onFailure.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Approve & Map to \(model.selectedGesture.displayName)") {
                        model.approveAndMapPreview()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44))
                        Text("No Plan Yet").font(.headline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Build Command")
    }
}

private struct TeachView: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Controlled Action Lab").font(.title2.bold())
                    Text("Records supported semantic controls only. Raw global input is never captured.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: model.recorderState.rawValue.uppercased(),
                    color: model.recorderState == .recording ? .red : .blue
                )
            }
            HStack {
                Button("Start") { model.startControlledRecording() }
                    .buttonStyle(.borderedProminent)
                Button("Add Safe Demo Sequence") { model.addRecordedDemoSteps() }
                    .disabled(model.recorderState != .recording)
                Button("Stop & Map to C Shape") { model.stopControlledRecording() }
                    .disabled(model.recorderState != .recording)
                Button("Cancel", role: .destructive) { model.cancelRecording() }
            }
            List(Array(model.recorderItems.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    Text("\(index + 1).")
                    VStack(alignment: .leading) {
                        Text(item.step.plainEnglish)
                        Text(String(format: "+%.1fs", item.offset)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(item.step.timeoutMs) ms").font(.caption)
                }
            }
            Text("Global recording is intentionally experimental and disabled in this release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Teach by Demo")
    }
}

private struct ProfilesView: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local-first profiles").font(.title2.bold())
            Text("Profiles use schemaVersion 1, reject unsupported future versions, and serialize secret references—not secret values.")
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 50)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Signal Demo").font(.headline)
                    Text("Preferred mode: Hybrid • Offline-safe seeded plan")
                }
                Spacer()
                Button("Use Profile") { model.useSeededProfile() }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }
        .padding()
        .navigationTitle("Profiles")
    }
}

struct SignalSettingsView: View {
    @EnvironmentObject private var model: SignalAppModel
    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        return "\(version) (\(build))"
    }
    private var commitLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "SignalCommit") as? String ?? "development"
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Picker("Mode", selection: Binding(get: { model.mode }, set: model.setMode)) {
                    ForEach(SignalMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Allow stationary One command in Hybrid after 900 ms", isOn: $model.oneCommandInHybrid)
                Text("Pinch always belongs to touch control and suspends command recognition.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Planner") {
                TextField("Public HTTPS endpoint", text: $model.endpoint)
                Button("Validate & Apply") { model.updatePlannerEndpoint() }
                Text("Localhost and private-network endpoints are blocked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Safety") {
                Text("Emergency shortcut: Control–Option–Command–H")
                Button("Emergency Stop", role: .destructive) { model.emergencyStop() }
            }
            Section("About") {
                LabeledContent("Version", value: versionLabel)
                LabeledContent("Commit", value: commitLabel)
                Text("Signal is a native macOS app. Camera frames stay in memory on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Settings")
    }
}

private struct DiagnosticsView: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Calibration & Diagnostics").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))]) {
                    MetricCard(name: "Capture FPS", value: String(format: "%.1f", model.diagnostics.captureFPS))
                    MetricCard(name: "Processed FPS", value: String(format: "%.1f", model.diagnostics.processedFPS))
                    MetricCard(name: "Vision latency", value: String(format: "%.1f ms", model.diagnostics.visionLatencyMs))
                    MetricCard(name: "End-to-end", value: String(format: "%.1f ms", model.diagnostics.endToEndLatencyMs))
                    MetricCard(name: "Dropped frames", value: "\(model.diagnostics.droppedFrames)")
                    MetricCard(name: "Axis lock", value: model.touchState.rawValue)
                }
                GroupBox("Built-in guide") {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Index-point moves the cursor relatively.", systemImage: "cursorarrow.motionlines")
                        Label("Quick thumb–index pinch and release clicks once.", systemImage: "cursorarrow.click")
                        Label("Hold pinch and move vertically to scroll.", systemImage: "arrow.up.and.down")
                        Label("Hold pinch and move horizontally to zoom.", systemImage: "arrow.left.and.right")
                        Label("Command gestures depend on the visible mode.", systemImage: "switch.2")
                    }
                    .padding(8)
                }
                GroupBox("Permission repair") {
                    Text("Open System Settings › Privacy & Security › Accessibility, remove stale Signal entries, add the exact packaged Signal.app, then relaunch. Output remains paused until you explicitly enable it.")
                        .padding(8)
                }
            }
            .padding()
        }
        .navigationTitle("Diagnostics")
    }
}

private struct MetricCard: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
