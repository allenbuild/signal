import AppKit
import SwiftUI

@MainActor
final class SignalApplicationDelegate: NSObject, NSApplicationDelegate {
    let runtime: SignalRuntime?
    private var runtimeStartScheduled = false
    private var runtimeStartTask: Task<Void, Never>?

    override init() {
        runtime = SignalApp.isTestHost(environment: ProcessInfo.processInfo.environment)
            ? nil
            : SignalRuntime()
        super.init()
    }

    init(
        environment: [String: String],
        runtimeFactory: () -> SignalRuntime
    ) {
        runtime = SignalApp.isTestHost(environment: environment)
            ? nil
            : runtimeFactory()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !runtimeStartScheduled, let runtime else { return }
        runtimeStartScheduled = true
        runtimeStartTask = Task { @MainActor [runtime] in
            runtime.start()
        }
    }

    func waitForScheduledRuntimeStartForTesting() async {
        await runtimeStartTask?.value
    }
}

@main
@MainActor
struct SignalApp: App {
    static let testHostEnvironmentKey = "SIGNAL_TEST_HOST"
    static let xctestBundlePathEnvironmentKey = "XCTestBundlePath"
    static let xctestSessionIdentifierEnvironmentKey = "XCTestSessionIdentifier"
    @NSApplicationDelegateAdaptor(SignalApplicationDelegate.self)
    private var applicationDelegate

    private var runtime: SignalRuntime? {
        applicationDelegate.runtime
    }

    static func isTestHost(environment: [String: String]) -> Bool {
        environment[testHostEnvironmentKey] == "1"
            || environment[xctestBundlePathEnvironmentKey]?.isEmpty == false
            || environment[xctestSessionIdentifierEnvironmentKey]?.isEmpty == false
    }

    var body: some Scene {
        MenuBarExtra {
            if let runtime {
                MenuSceneRoot(runtime: runtime)
            } else {
                EmptyView()
            }
        } label: {
            if let runtime {
                MenuBarLabel(model: runtime.uiModel)
            } else {
                Label("Signal Test Host", systemImage: "hand.raised.slash")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Signal Calibration", id: "calibration") {
            if let runtime {
                CalibrationSceneRoot(runtime: runtime)
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 1_180, height: 760)
    }
}

@MainActor
private struct MenuBarLabel: View {
    @ObservedObject var model: SignalUIModel

    var body: some View {
        Label("Signal", systemImage: model.statusSymbol)
    }
}

@MainActor
final class SignalRuntime: ObservableObject {
    let state: AppState
    let uiModel: SignalUIModel
    let settingsStore: SettingsStore
    let calibrationViewModel: CalibrationViewModel
    let launchAtLoginViewModel: LaunchAtLoginViewModel
    let previewLayerController: CameraPreviewLayerController?
    let coordinator: AppCoordinator
    private var settingsWindowController: SignalSettingsWindowController?
    private(set) var hasStarted = false

    var hasCreatedSettingsWindowController: Bool {
        settingsWindowController != nil
    }

    init() {
        let state = AppState()
        let uiModel = SignalUIModel()
        let settingsStore = SettingsStore()
        let calibrationViewModel = CalibrationViewModel()
        let permissionService = PermissionStatusService()
        let launchAtLoginController = LaunchAtLoginController()
        let launchAtLoginViewModel = LaunchAtLoginViewModel(
            controller: launchAtLoginController
        )

        let tuning = settingsStore.tuning.validated()

        let inputController = MacOSInputController(
            tuning: tuning,
            // Production zoom is always macOS Accessibility screen
            // magnification so applications keep their page/document zoom.
            userZoomProfiles: ZoomOutputPolicy.productionProfiles(
                ignoring: settingsStore.zoomProfiles
            ),
            screenZoomShortcutsEnabled: settingsStore.screenZoomShortcutsEnabled
        )
        let gesturePipeline = GesturePipeline(
            tuning: tuning,
            inputSink: inputController
        )
        let trackingService = TrackingService(tuning: tuning)
        let cameraService = CameraService(frameConsumer: trackingService)
        trackingService.generationValidator = { [weak cameraService] generation in
            cameraService?.isGenerationCurrent(generation) ?? false
        }
        inputController.captureGenerationValidator = { [weak cameraService] generation in
            cameraService?.isGenerationCurrent(generation) ?? false
        }

        let lifecycleMonitor = AppLifecycleMonitor()
        let emergencyMonitor = EmergencyShortcutMonitor(
            ignoredEventMarker: inputController.generatedEventMarker
        )
        let coordinator = AppCoordinator(
            state: state,
            uiModel: uiModel,
            settingsStore: settingsStore,
            calibrationViewModel: calibrationViewModel,
            cameraService: cameraService,
            trackingService: trackingService,
            gesturePipeline: gesturePipeline,
            inputController: inputController,
            permissionService: permissionService,
            launchAtLoginViewModel: launchAtLoginViewModel,
            lifecycleMonitor: lifecycleMonitor,
            emergencyMonitor: emergencyMonitor
        )

        self.state = state
        self.uiModel = uiModel
        self.settingsStore = settingsStore
        self.calibrationViewModel = calibrationViewModel
        self.launchAtLoginViewModel = launchAtLoginViewModel
        previewLayerController = cameraService.makePreviewLayerController()
        self.coordinator = coordinator
        if let previewLayerController {
            coordinator.setPreviewLayerController(previewLayerController)
        }
    }

    init(
        testingWith settingsStore: SettingsStore,
        launchAtLoginViewModel: LaunchAtLoginViewModel
    ) {
        let state = AppState()
        self.state = state
        uiModel = SignalUIModel()
        self.settingsStore = settingsStore
        calibrationViewModel = CalibrationViewModel()
        self.launchAtLoginViewModel = launchAtLoginViewModel
        previewLayerController = nil
        coordinator = AppCoordinator(state: state)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        settingsStore.synchronizePersistenceIfNeeded()
        coordinator.startRuntime()
    }

    func openSettings() {
        let controller: SignalSettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            let created = SignalSettingsWindowController(
                store: settingsStore,
                launchAtLogin: launchAtLoginViewModel
            )
            settingsWindowController = created
            controller = created
        }
        controller.showWindow()
    }
}

@MainActor
private struct MenuSceneRoot: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var runtime: SignalRuntime

    var body: some View {
        MenuBarContentView(
            model: runtime.uiModel,
            settings: runtime.settingsStore,
            launchAtLogin: runtime.launchAtLoginViewModel,
            actions: runtime.coordinator.makeActions(openCalibrationWindow: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "calibration")
            }, openSettingsWindow: { runtime.openSettings() })
        )
    }
}

@MainActor
private struct CalibrationSceneRoot: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var runtime: SignalRuntime

    var body: some View {
        CalibrationView(
            previewLayer: runtime.previewLayerController?.layer,
            viewModel: runtime.calibrationViewModel,
            settings: runtime.settingsStore,
            uiModel: runtime.uiModel,
            actions: runtime.coordinator.makeActions(openCalibrationWindow: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "calibration")
            }, openSettingsWindow: { runtime.openSettings() })
        )
        .onAppear {
            runtime.previewLayerController?.refreshConnectionConfiguration()
            runtime.coordinator.calibrationDidOpen()
        }
    }
}

@MainActor
final class SignalSettingsWindowController {
    private let store: SettingsStore
    private let launchAtLogin: LaunchAtLoginViewModel
    private var windowController: NSWindowController?

    var hasLoadedWindow: Bool {
        windowController != nil
    }

    init(store: SettingsStore, launchAtLogin: LaunchAtLoginViewModel) {
        self.store = store
        self.launchAtLogin = launchAtLogin
    }

    @discardableResult
    func loadWindow() -> NSWindowController {
        launchAtLogin.refresh()
        if let windowController {
            return windowController
        }

        let root = SettingsView(store: store, launchAtLogin: launchAtLogin)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Signal Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: root)
        let created = NSWindowController(window: window)
        windowController = created
        return created
    }

    func showWindow() {
        let windowController = loadWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }
}
