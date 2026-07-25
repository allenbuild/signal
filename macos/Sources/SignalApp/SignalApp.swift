import AppKit
import SignalCore
import SwiftUI

@main
struct SignalApplication: App {
    @StateObject private var model = SignalAppModel()

    var body: some Scene {
        WindowGroup("Signal") {
            SignalCommandCenter()
                .environmentObject(model)
                .frame(minWidth: 1_040, minHeight: 680)
                .task { model.startRuntimeOnce() }
        }
        .commands {
            CommandMenu("Signal") {
                Button("Pause / Enable") { model.toggleOutput() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Cycle Mode") { model.cycleMode() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Emergency Stop") { model.emergencyStop() }
                    .keyboardShortcut("h", modifiers: [.command, .option, .control])
            }
        }

        MenuBarExtra {
            SignalMenu()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isPaused ? "hand.raised.slash.fill" : "hand.raised.fill")
        }

        Settings {
            SignalSettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 420)
        }
    }
}

enum SignalSection: String, CaseIterable, Identifiable {
    case live = "Live"
    case gestures = "Gestures"
    case build = "Build Command"
    case teach = "Teach by Demo"
    case profiles = "Profiles"
    case settings = "Settings"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .live: return "waveform.path.ecg"
        case .gestures: return "hand.raised"
        case .build: return "wand.and.stars"
        case .teach: return "record.circle"
        case .profiles: return "person.2"
        case .settings: return "gear"
        case .diagnostics: return "gauge.with.dots.needle.67percent"
        }
    }
}

@MainActor
final class SignalAppModel: ObservableObject {
    @Published var isPaused = true
    @Published var mode: SignalMode = .hybrid
    @Published var selectedSection: SignalSection = .live
    @Published var selectedGesture: CommandGesture = .thumbsUp
    @Published var touchState: TouchState = .idle
    @Published var candidate: CommandGesture?
    @Published var confidence = 0.0
    @Published var holdProgress = 0.0
    @Published var statusMessage = "Output paused — enable explicitly when ready"
    @Published var cameraStatus = "Camera is off"
    @Published var diagnostics = CameraDiagnostics()
    @Published var receipts: [ActionReceipt] = []
    @Published var prompt = "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord."
    @Published var previewPlan: ActionPlan?
    @Published var plannerStatus = "Public HTTPS planner with offline fallback"
    @Published var isPlanning = false
    @Published var recorderState: RecorderState = .idle
    @Published var recorderItems: [RecordedTimelineItem] = []
    @Published var oneCommandInHybrid = false
    @Published var endpoint = "https://signal-hand.app/api/v1/plan"

    let safetyGate = SafetyGate()
    private let events = QuartzEventPoster()
    private lazy var performer = SystemActionPerformer(events: events, safetyGate: safetyGate)
    private let executor = MacroExecutor()
    private let planner = PlannerClient()
    private let camera = CameraHandTrackingService()
    private let hotkey = EmergencyHotkeyMonitor()
    private var touchEngine = TouchEngine()
    private var classifier = CommandGestureClassifier()
    private var activationEngine = CommandActivationEngine()
    private var recorder = ControlledDemoRecorder()
    private var runtimeStarted = false
    private var lastHandCenter: Point2D?
    private var oneStationarySince: TimeInterval?
    private var plans: [CommandGesture: ActionPlan] = Dictionary(
        uniqueKeysWithValues: SeededContent.demoProfile().mappings.map { ($0.gesture, $0.plan) }
    )

    init() {
        previewPlan = SeededContent.focusPlan()
    }

    func startRuntimeOnce() {
        guard !runtimeStarted else { return }
        runtimeStarted = true
        hotkey.start { [weak self] in
            Task { @MainActor in self?.emergencyStop() }
        }
        camera.onHand = { [weak self] hand, metrics in
            Task { @MainActor in self?.process(hand, metrics: metrics) }
        }
        camera.onTrackingLoss = { [weak self] in
            Task { @MainActor in self?.trackingLost() }
        }
        statusMessage = "Runtime ready; output remains paused"
    }

    func toggleOutput() {
        if isPaused {
            guard events.accessibilityTrusted(prompt: true) else {
                statusMessage = "Accessibility permission required for system control"
                return
            }
            safetyGate.enableExplicitly()
            isPaused = false
            statusMessage = "\(mode.displayName) Mode enabled"
        } else {
            pause(reason: .user)
        }
    }

    func pause(reason: PauseReason) {
        safetyGate.pause(reason)
        isPaused = true
        _ = touchEngine.cancel()
        touchState = .idle
        activationEngine.cancel()
        candidate = nil
        holdProgress = 0
        Task { await executor.cancel() }
        statusMessage = reason == .emergency ? "EMERGENCY STOP — explicit re-enable required" : "Output paused"
    }

    func emergencyStop() {
        pause(reason: .emergency)
    }

    func cycleMode() {
        let modes = SignalMode.allCases
        let next = modes.index(after: modes.firstIndex(of: mode)!)
        setMode(next == modes.endIndex ? modes[0] : modes[next])
    }

    func setMode(_ value: SignalMode) {
        if !isPaused {
            pause(reason: .user)
        }
        mode = value
        _ = touchEngine.cancel()
        activationEngine.cancel()
        touchState = .idle
        candidate = nil
        holdProgress = 0
        statusMessage = "\(value.displayName) Mode" + (isPaused ? " — paused" : "")
    }

    func useSeededProfile() {
        let profile = SeededContent.demoProfile()
        plans = Dictionary(uniqueKeysWithValues: profile.mappings.map { ($0.gesture, $0.plan) })
        setMode(profile.preferredMode)
        statusMessage = "Loaded all canonical Signal Hero mappings"
    }

    func startCamera() {
        cameraStatus = "Requesting camera permission…"
        Task {
            let started = await camera.requestAndStart()
            cameraStatus = started ? "Camera on — frames stay on this Mac" : "Camera permission unavailable"
        }
    }

    func stopCamera() {
        camera.stop()
        cameraStatus = "Camera is off"
        trackingLost()
    }

    func buildPlan() {
        isPlanning = true
        plannerStatus = "Validating with public planner…"
        Task {
            let result = await planner.plan(prompt, targetGesture: selectedGesture)
            isPlanning = false
            previewPlan = result.response.plan
            if case .seededOffline(let reason) = result.source {
                plannerStatus = "Offline validated fallback: \(reason)"
            } else {
                plannerStatus = "Plan received and validated over public HTTPS"
            }
            if result.response.status == .needsClarification {
                plannerStatus = result.response.question ?? "More details required"
            }
        }
    }

    func approveAndMapPreview() {
        guard var plan = previewPlan else { return }
        plan.approved = true
        do {
            try ActionPlanValidator().validate(plan)
            plans[selectedGesture] = plan
            previewPlan = plan
            statusMessage = "Mapped \(plan.name) to \(selectedGesture.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func testSelectedGesture() {
        runPlan(for: selectedGesture)
    }

    func startControlledRecording() {
        recorder.beginCountdown()
        recorder.typedTextConsent = true
        recorder.start(at: ProcessInfo.processInfo.systemUptime)
        recorderState = recorder.state
        recorderItems = recorder.items
        statusMessage = "Recording controlled actions — no global raw events"
    }

    func addRecordedDemoSteps() {
        let now = ProcessInfo.processInfo.systemUptime
        do {
            try recorder.record(ActionStep(
                action: .openApplication,
                parameters: [
                    "bundleIdentifier": .string("com.apple.TextEdit"),
                    "applicationName": .string("TextEdit")
                ]
            ), at: now)
            try recorder.record(ActionStep(
                action: .keyboardShortcut,
                parameters: ["key": .string("n"), "modifiers": .array([.string("command")])]
            ), at: now + 0.5)
            try recorder.record(ActionStep(
                action: .typeText,
                parameters: [
                    "text": .string("Signal replayed this workflow with a hand gesture."),
                    "containsSensitiveData": .bool(false)
                ]
            ), at: now + 1)
            recorderItems = recorder.items
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopControlledRecording() {
        do {
            var plan = try recorder.stop(name: "Replay recorded note")
            plan.approved = true
            plans[.cShape] = plan
            previewPlan = plan
            selectedGesture = .cShape
            recorderState = recorder.state
            recorderItems = recorder.items
            statusMessage = "Editable timeline mapped to C Shape"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelRecording() {
        recorder.cancel()
        recorderState = recorder.state
        recorderItems = []
    }

    func mappedPlan(for gesture: CommandGesture) -> ActionPlan? {
        plans[gesture]
    }

    func updatePlannerEndpoint() {
        guard let url = URL(string: endpoint) else {
            statusMessage = "Invalid endpoint"
            return
        }
        Task {
            do {
                try await planner.update(configuration: PlannerConfiguration(endpoint: url))
                statusMessage = "Planner endpoint updated"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func process(_ hand: HandLandmarks, metrics: CameraDiagnostics) {
        diagnostics = metrics
        cameraStatus = "Live — camera data stays in memory"
        let gestureCandidate = classifier.classify(hand)
        candidate = gestureCandidate?.gesture
        confidence = gestureCandidate?.confidence ?? 0
        let scale = palmScale(hand)
        let center = hand[.middleMCP]?.location ?? hand[.wrist]?.location ?? .zero
        let pinch = (hand[.thumbTip]?.location.distance(to: hand[.indexTip]?.location ?? .zero) ?? 1) / scale
        let pointerPose = gestureCandidate?.gesture == .one

        let previous = lastHandCenter
        if pointerPose, let previous, center.distance(to: previous) / scale < 0.035 {
            if oneStationarySince == nil { oneStationarySince = hand.timestamp }
        } else {
            oneStationarySince = nil
        }
        lastHandCenter = center

        if mode != .command {
            let outputs = touchEngine.process(TouchFrame(
                timestamp: hand.timestamp,
                trackingValid: true,
                pointerPose: pointerPose,
                pinchDistance: pinch,
                handCenter: center,
                palmScale: scale
            ), outputEnabled: !isPaused)
            apply(outputs)
        } else {
            _ = touchEngine.cancel()
        }

        let context = CommandContext(
            mode: mode,
            outputPaused: isPaused,
            pinchActive: touchEngine.isPinchActive,
            recording: recorder.state == .recording,
            oneCommandEnabledInHybrid: oneCommandInHybrid,
            onePoseStationaryDuration: oneStationarySince.map { hand.timestamp - $0 } ?? 0
        )
        switch activationEngine.update(candidate: gestureCandidate, at: hand.timestamp, context: context) {
        case .progressing(let gesture, let progress, let confidence):
            candidate = gesture
            holdProgress = progress
            self.confidence = confidence
        case .triggered(let gesture):
            holdProgress = 1
            runPlan(for: gesture)
        case .releaseRequired:
            holdProgress = 1
        case .idle:
            holdProgress = 0
        }
    }

    private func apply(_ outputs: [TouchOutput]) {
        guard !isPaused else { return }
        for output in outputs {
            switch output {
            case .pointer(let delta): events.movePointer(relative: delta)
            case .click: events.leftClick()
            case .scroll(let amount): events.scroll(amount)
            case .zoom(let steps): events.zoom(steps: steps)
            case .state(let state): touchState = state
            }
        }
    }

    private func trackingLost() {
        _ = touchEngine.cancel()
        activationEngine.cancel()
        touchState = .idle
        candidate = nil
        holdProgress = 0
        lastHandCenter = nil
        oneStationarySince = nil
    }

    private func runPlan(for gesture: CommandGesture) {
        guard !isPaused else {
            statusMessage = "Enable output before running commands"
            return
        }
        guard let plan = plans[gesture] else {
            statusMessage = "No command mapped to \(gesture.displayName)"
            return
        }
        statusMessage = "Running \(plan.name)…"
        Task {
            let run = await executor.execute(
                plan,
                performer: SafetyGatedPerformer(gate: safetyGate, underlying: performer),
                confirmations: ApprovedPlanConfirmations()
            )
            receipts.insert(contentsOf: run.stepReceipts.reversed(), at: 0)
            receipts = Array(receipts.prefix(20))
            statusMessage = "\(plan.name): \(run.status.rawValue)"
        }
    }

    private func palmScale(_ hand: HandLandmarks) -> Double {
        if let index = hand[.indexMCP]?.location, let little = hand[.littleMCP]?.location {
            return max(index.distance(to: little), 0.03)
        }
        if let wrist = hand[.wrist]?.location, let middle = hand[.middleMCP]?.location {
            return max(wrist.distance(to: middle), 0.03)
        }
        return 0.15
    }
}

struct SignalMenu: View {
    @EnvironmentObject private var model: SignalAppModel

    var body: some View {
        Button(model.isPaused ? "Enable Output…" : "Pause Output") { model.toggleOutput() }
        Divider()
        Picker("Mode", selection: Binding(get: { model.mode }, set: model.setMode)) {
            ForEach(SignalMode.allCases) { mode in Text(mode.displayName).tag(mode) }
        }
        Divider()
        Button("Open Signal") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Signal" }?.makeKeyAndOrderFront(nil)
        }
        Button("Open Calibration") {
            model.selectedSection = .diagnostics
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Emergency Stop") { model.emergencyStop() }
        Divider()
        Button("Quit Signal") { NSApp.terminate(nil) }
    }
}
