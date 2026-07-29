import AppKit
import Combine
import Foundation
import XCTest
@testable import Signal

@MainActor
final class SettingsAndCoordinatorTests: XCTestCase {
    func testExplicitTestHostPolicyDoesNotSelectProductionRuntime() async throws {
        XCTAssertTrue(SignalApp.isTestHost(
            environment: ProcessInfo.processInfo.environment
        ))
        XCTAssertTrue(SignalApp.isTestHost(environment: [
            SignalApp.testHostEnvironmentKey: "1"
        ]))
        XCTAssertTrue(SignalApp.isTestHost(environment: [
            SignalApp.xctestBundlePathEnvironmentKey: "/tmp/SignalTests.xctest"
        ]))
        XCTAssertTrue(SignalApp.isTestHost(environment: [
            SignalApp.xctestSessionIdentifierEnvironmentKey: UUID().uuidString
        ]))
        XCTAssertFalse(SignalApp.isTestHost(environment: [:]))
        XCTAssertFalse(SignalApp.isTestHost(environment: [
            SignalApp.testHostEnvironmentKey: "0"
        ]))
        XCTAssertFalse(SignalApp.isTestHost(environment: [
            SignalApp.xctestBundlePathEnvironmentKey: "",
            SignalApp.xctestSessionIdentifierEnvironmentKey: "",
            "XCTestConfigurationFilePath": ""
        ]))
        XCTAssertFalse(SignalApp.isTestHost(environment: [
            "XCTestConfigurationFilePath": "/tmp/ignored.xctestconfiguration"
        ]))

        let suiteName = "com.allenxu.SignalTests.applicationDelegate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = SignalRuntime(
            testingWith: SettingsStore(defaults: defaults),
            launchAtLoginViewModel: LaunchAtLoginViewModel(
                controller: LaunchAtLoginControllerSpy()
            )
        )
        var factoryCallCount = 0

        let testDelegate = SignalApplicationDelegate(environment: [
            SignalApp.testHostEnvironmentKey: "1"
        ]) {
            factoryCallCount += 1
            return runtime
        }
        XCTAssertNil(testDelegate.runtime)
        XCTAssertEqual(factoryCallCount, 0)

        testDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await testDelegate.waitForScheduledRuntimeStartForTesting()
        XCTAssertFalse(runtime.hasStarted)
        XCTAssertEqual(factoryCallCount, 0)

        let applicationDelegate = SignalApplicationDelegate(environment: [:]) {
            factoryCallCount += 1
            return runtime
        }
        XCTAssertTrue(applicationDelegate.runtime === runtime)
        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertFalse(runtime.hasStarted)
        XCTAssertNil(defaults.data(forKey: SettingsStore.storageKey))

        applicationDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        XCTAssertFalse(runtime.hasStarted)
        await applicationDelegate.waitForScheduledRuntimeStartForTesting()
        XCTAssertTrue(runtime.hasStarted)
        let persistedSettings = defaults.data(forKey: SettingsStore.storageKey)
        XCTAssertNotNil(persistedSettings)

        applicationDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await applicationDelegate.waitForScheduledRuntimeStartForTesting()
        XCTAssertTrue(runtime.hasStarted)
        XCTAssertEqual(defaults.data(forKey: SettingsStore.storageKey), persistedSettings)
        XCTAssertEqual(factoryCallCount, 1)
    }

    func testSettingsStoreInitializationDefersPersistence() throws {
        let suiteName = "com.allenxu.SignalTests.deferredPersistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.screenZoomShortcutsEnabled)
        XCTAssertNil(defaults.data(forKey: SettingsStore.storageKey))

        store.synchronizePersistenceIfNeeded()
        XCTAssertNotNil(defaults.data(forKey: SettingsStore.storageKey))
    }

    func testLaunchAtLoginRefreshPublishesOnlyChangedState() {
        let controller = LaunchAtLoginControllerSpy()
        let viewModel = LaunchAtLoginViewModel(controller: controller)
        var publicationCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            publicationCount += 1
        }

        viewModel.refresh()
        XCTAssertEqual(publicationCount, 0)

        controller.enabled = true
        viewModel.refresh()
        XCTAssertEqual(publicationCount, 1)
        XCTAssertTrue(viewModel.isEnabled)
        withExtendedLifetime(cancellable) {}
    }

    func testSettingsWindowControllerInitializationIsGraphFree() throws {
        let suiteName = "com.allenxu.SignalTests.settingsWindowInit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchController = LaunchAtLoginControllerSpy()
        let launchViewModel = LaunchAtLoginViewModel(controller: launchController)
        let initialStatusReads = launchController.statusReadCount

        let controller = SignalSettingsWindowController(
            store: SettingsStore(defaults: defaults),
            launchAtLogin: launchViewModel
        )

        XCTAssertFalse(controller.hasLoadedWindow)
        XCTAssertEqual(launchController.statusReadCount, initialStatusReads)
        XCTAssertEqual(launchController.setEnabledRequests, [])
        XCTAssertEqual(launchController.openSettingsCount, 0)
    }

    func testSettingsWindowLoadsHostingGraphOnceOnExplicitRequest() throws {
        let suiteName = "com.allenxu.SignalTests.settingsWindowLoad.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchController = LaunchAtLoginControllerSpy()
        let controller = SignalSettingsWindowController(
            store: SettingsStore(defaults: defaults),
            launchAtLogin: LaunchAtLoginViewModel(controller: launchController)
        )

        let first = controller.loadWindow()
        defer { first.close() }
        first.window?.contentView?.layoutSubtreeIfNeeded()
        let second = controller.loadWindow()

        XCTAssertTrue(controller.hasLoadedWindow)
        XCTAssertTrue(first === second)
        XCTAssertNotNil(first.window?.contentViewController)
        XCTAssertEqual(launchController.setEnabledRequests, [])
        XCTAssertEqual(launchController.openSettingsCount, 0)
    }

    func testRuntimeConstructionIsPassiveDisabledAndWindowFree() throws {
        let suiteName = "com.allenxu.SignalTests.passiveRuntime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let runtime = SignalRuntime(
            testingWith: store,
            launchAtLoginViewModel: LaunchAtLoginViewModel(
                controller: LaunchAtLoginControllerSpy()
            )
        )

        XCTAssertFalse(runtime.hasStarted)
        XCTAssertFalse(runtime.hasCreatedSettingsWindowController)
        XCTAssertNil(runtime.previewLayerController)
        XCTAssertEqual(runtime.state.controlIntent, .disabled)
        XCTAssertEqual(runtime.state.status, .disabled)
        XCTAssertNil(defaults.data(forKey: SettingsStore.storageKey))

        runtime.start()
        let persisted = defaults.data(forKey: SettingsStore.storageKey)
        XCTAssertTrue(runtime.hasStarted)
        XCTAssertNotNil(persisted)
        XCTAssertFalse(runtime.hasCreatedSettingsWindowController)

        runtime.start()
        XCTAssertEqual(defaults.data(forKey: SettingsStore.storageKey), persisted)
        XCTAssertEqual(runtime.state.controlIntent, .disabled)
    }

    func testSettingsRoundTripProfilesAndSafeDefaultRestore() throws {
        let suiteName = "com.allenxu.SignalTests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.screenZoomShortcutsEnabled)
        store.setScreenZoomShortcutsEnabled(true)
        var custom = GestureTuning.safeDefaults
        custom.minimumLandmarkConfidence = 0.65
        custom.poseStabilityDuration = 0.150
        custom.pointerSensitivity = 500
        custom.pointerDeadZone = 0.018
        custom.pointerAcceleration = 0.20
        custom.quickPinchMaximumDuration = 0.28
        custom.pinchScrollActivationDisplacement = 0.07
        custom.pinchScrollHoldDuration = 0.20
        custom.scrollStabilizationFrames = 4
        custom.scrollSensitivityX = 40
        custom.scrollSensitivityY = 55
        custom.naturalScrolling = false
        custom.zoomSensitivity = 1.20
        custom.zoomStepThreshold = 0.25
        custom.oneEuroMinimumCutoff = 2.0
        custom.oneEuroDerivativeCutoff = 1.2
        custom.oneEuroBeta = 0.40
        XCTAssertTrue(store.setTuning(custom))

        let profile = ZoomApplicationProfileSetting(
            bundleIdentifier: " com.example.Reader ",
            displayName: " Example Reader ",
            zoomIn: ZoomShortcutSetting(keyEquivalent: "+", command: true, shift: true),
            zoomOut: ZoomShortcutSetting(keyEquivalent: "-", command: true),
            reset: ZoomShortcutSetting(keyEquivalent: "0", command: true)
        )
        XCTAssertTrue(store.upsertZoomProfile(profile))

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.tuning, custom)
        XCTAssertEqual(reloaded.zoomProfiles.count, 1)
        XCTAssertEqual(reloaded.zoomProfiles.first?.bundleIdentifier, "com.example.Reader")
        XCTAssertEqual(reloaded.zoomProfiles.first?.displayName, "Example Reader")
        XCTAssertTrue(reloaded.screenZoomShortcutsEnabled)

        reloaded.resetSafeDefaults()
        XCTAssertEqual(reloaded.tuning, .safeDefaults)
        XCTAssertEqual(reloaded.zoomProfiles, [])
        XCTAssertFalse(reloaded.screenZoomShortcutsEnabled)

        let afterReset = SettingsStore(defaults: defaults)
        XCTAssertEqual(afterReset.tuning, .safeDefaults)
        XCTAssertEqual(afterReset.zoomProfiles, [])
        XCTAssertFalse(afterReset.screenZoomShortcutsEnabled)
    }

    func testProductionCoordinatorUsesValidatedApplicationZoomProfile() {
        let backend = FakeInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider("com.google.Chrome"),
            clock: FakeInputClock(),
            screenZoomShortcutsEnabled: true
        )
        let coordinator = AppCoordinator(
            state: AppState(),
            inputController: controller
        )
        let legacy = ZoomApplicationProfileSetting(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Legacy Chrome page zoom",
            zoomIn: ZoomShortcutSetting(keyEquivalent: "+", command: true, shift: true),
            zoomOut: ZoomShortcutSetting(keyEquivalent: "-", command: true),
            reset: ZoomShortcutSetting(keyEquivalent: "0", command: true)
        )
        XCTAssertEqual(
            ZoomOutputPolicy.productionProfiles(ignoring: [legacy])["com.google.Chrome"],
            ZoomProfileAdapter.profiles(from: [legacy])["com.google.Chrome"]
        )

        coordinator.applySettingsConfiguration(
            tuning: .safeDefaults,
            profiles: [legacy],
            screenZoomShortcutsEnabled: true
        )
        controller.setOutputGate(enabled: true)
        _ = controller.snapshot()
        _ = controller.snapshot()
        XCTAssertTrue(controller.isOutputEnabled)

        controller.handle(.zoom(delta: GestureTuning.safeDefaults.zoomStepThreshold))
        _ = controller.snapshot()
        _ = controller.snapshot()
        XCTAssertEqual(
            backend.events(),
            ZoomShortcut(keyCode: 24, modifiers: [.command, .shift]).eventPair
        )
    }

    func testLegacyScreenZoomConfirmationDoesNotBlockApplicationZoom() throws {
        let suiteName = "com.allenxu.SignalTests.screenZoomMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seed = SettingsStore(defaults: defaults)
        XCTAssertTrue(seed.setTuning(.safeDefaults))
        let current = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        defaults.set(
            try settingsDataWithoutScreenZoomConfirmation(current),
            forKey: SettingsStore.storageKey
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertFalse(migrated.screenZoomShortcutsEnabled)

        let backend = FakeInputBackend()
        let controller = MacOSInputController(
            backend: backend,
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock(),
            screenZoomShortcutsEnabled: migrated.screenZoomShortcutsEnabled
        )
        controller.setOutputGate(enabled: true)
        _ = controller.snapshot()
        _ = controller.snapshot()
        controller.handle(.zoom(delta: GestureTuning.safeDefaults.zoomStepThreshold))
        _ = controller.snapshot()
        _ = controller.snapshot()
        XCTAssertEqual(
            backend.events(),
            ZoomApplicationProfile.standard.zoomIn.eventPair
        )
    }

    func testLegacyMiddleThumbDefaultsMigrationRetunesOnlyTheOldDefault() throws {
        let suiteName = "com.allenxu.SignalTests.middleThumbMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seedStore = SettingsStore(defaults: defaults)
        var legacyTuning = GestureTuning.safeDefaults
        legacyTuning.pointerSensitivity = 600
        legacyTuning.pointerDeadZone = 0.019
        legacyTuning.quickPinchMaximumDuration = 0.27
        legacyTuning.scrollSensitivityY = 51
        XCTAssertTrue(seedStore.setTuning(legacyTuning))
        XCTAssertTrue(seedStore.upsertZoomProfile(ZoomApplicationProfileSetting(
            bundleIdentifier: "com.example.LegacyReader",
            displayName: "Legacy Reader",
            zoomIn: ZoomShortcutSetting(keyEquivalent: "+", command: true),
            zoomOut: ZoomShortcutSetting(keyEquivalent: "-", command: true),
            reset: nil
        )))

        let currentData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        let legacyData = try settingsDataWithoutScrollStabilization(currentData)
        defaults.set(legacyData, forKey: SettingsStore.storageKey)

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.tuning.pointerSensitivity, 400)
        XCTAssertEqual(migrated.tuning.pointerDeadZone, 0.019)
        XCTAssertEqual(migrated.tuning.quickPinchMaximumDuration, 0.27)
        XCTAssertEqual(migrated.tuning.scrollSensitivityY, 51)
        XCTAssertEqual(migrated.tuning.scrollStabilizationFrames, 2)
        XCTAssertEqual(migrated.zoomProfiles.map(\.bundleIdentifier), ["com.example.LegacyReader"])
        XCTAssertNotNil(migrated.lastValidationMessage)

        // Loading remains side-effect-free; the repair is persisted only once startup is active.
        XCTAssertEqual(defaults.data(forKey: SettingsStore.storageKey), legacyData)
        migrated.synchronizePersistenceIfNeeded()

        let persistedData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: persistedData) as? [String: Any]
        )
        let persistedTuning = try XCTUnwrap(root["tuning"] as? [String: Any])
        XCTAssertEqual(
            try XCTUnwrap(persistedTuning["pointerSensitivity"] as? NSNumber).doubleValue,
            400
        )
        XCTAssertEqual(
            try XCTUnwrap(persistedTuning["scrollStabilizationFramesStorage"] as? NSNumber).intValue,
            2
        )

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.tuning, migrated.tuning)
        XCTAssertEqual(reloaded.zoomProfiles, migrated.zoomProfiles)
    }

    func testLegacyMiddleThumbMigrationPreservesCustomizedPointerSensitivity() throws {
        let suiteName = "com.allenxu.SignalTests.middleThumbCustomPointer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seedStore = SettingsStore(defaults: defaults)
        var customized = GestureTuning.safeDefaults
        customized.pointerSensitivity = 500
        customized.pointerDeadZone = 0.021
        XCTAssertTrue(seedStore.setTuning(customized))

        let currentData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        defaults.set(
            try settingsDataWithoutScrollStabilization(currentData),
            forKey: SettingsStore.storageKey
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.tuning.pointerSensitivity, 500)
        XCTAssertEqual(migrated.tuning.pointerDeadZone, 0.021)
        XCTAssertEqual(migrated.tuning.scrollStabilizationFrames, 2)
    }

    func testOneHandAxisMigrationRetunesOnlyExactFormerDefaults() throws {
        let suiteName = "com.allenxu.SignalTests.oneHandAxisMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seedStore = SettingsStore(defaults: defaults)
        var formerDefaults = GestureTuning.safeDefaults
        formerDefaults.pinchCloseRatio = 0.22
        formerDefaults.pinchOpenRatio = 0.32
        formerDefaults.pinchIntentRatio = 0.40
        formerDefaults.quickPinchMaximumDuration = 0.300
        formerDefaults.pinchMotionActivationDisplacement = 0.06
        formerDefaults.zoomSensitivity = 1
        XCTAssertTrue(seedStore.setTuning(formerDefaults))

        let currentData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        defaults.set(
            try settingsDataWithoutOneHandAxisVersion(currentData),
            forKey: SettingsStore.storageKey
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.tuning.pinchCloseRatio, 0.28)
        XCTAssertEqual(migrated.tuning.pinchOpenRatio, 0.38)
        XCTAssertEqual(migrated.tuning.pinchIntentRatio, 0.46)
        XCTAssertEqual(migrated.tuning.quickPinchMaximumDuration, 0.400)
        XCTAssertEqual(migrated.tuning.pinchMotionActivationDisplacement, 0.04)
        XCTAssertEqual(migrated.tuning.scrollStabilizationFrames, 1)
        XCTAssertEqual(migrated.tuning.scrollAxisLockRatio, 1.15)
        XCTAssertEqual(migrated.tuning.scrollSensitivityY, 120)
        XCTAssertEqual(migrated.tuning.zoomSensitivity, 2)
        XCTAssertEqual(migrated.tuning.zoomStepThreshold, 0.06)
        XCTAssertNotNil(migrated.lastValidationMessage)
    }

    func testOneHandAxisVersionTwoMigrationRepairsWeakMotionDefaults() throws {
        let suiteName = "com.allenxu.SignalTests.oneHandAxisV2Migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seedStore = SettingsStore(defaults: defaults)
        var versionOne = GestureTuning.safeDefaults
        versionOne.pinchMotionActivationDisplacement = 0.08
        versionOne.scrollStabilizationFrames = 2
        versionOne.scrollAxisLockRatio = 1.25
        versionOne.scrollSensitivityY = 63
        versionOne.zoomStepThreshold = 0.08
        XCTAssertTrue(seedStore.setTuning(versionOne))

        let currentData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        defaults.set(
            try settingsData(currentData, withOneHandAxisVersion: 1),
            forKey: SettingsStore.storageKey
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.tuning.pinchMotionActivationDisplacement, 0.04)
        XCTAssertEqual(migrated.tuning.scrollStabilizationFrames, 1)
        XCTAssertEqual(migrated.tuning.scrollAxisLockRatio, 1.15)
        XCTAssertEqual(migrated.tuning.scrollSensitivityY, 120)
        XCTAssertEqual(migrated.tuning.zoomStepThreshold, 0.06)
        XCTAssertNotNil(migrated.lastValidationMessage)
    }

    func testOneHandAxisMigrationPreservesCustomizedGestureValues() throws {
        let suiteName = "com.allenxu.SignalTests.oneHandAxisCustom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seedStore = SettingsStore(defaults: defaults)
        var custom = GestureTuning.safeDefaults
        custom.pinchCloseRatio = 0.24
        custom.pinchOpenRatio = 0.34
        custom.pinchIntentRatio = 0.43
        custom.quickPinchMaximumDuration = 0.27
        custom.pinchMotionActivationDisplacement = 0.07
        custom.zoomSensitivity = 1.5
        XCTAssertTrue(seedStore.setTuning(custom))

        let currentData = try XCTUnwrap(defaults.data(forKey: SettingsStore.storageKey))
        defaults.set(
            try settingsDataWithoutOneHandAxisVersion(currentData),
            forKey: SettingsStore.storageKey
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.tuning.pinchCloseRatio, 0.24)
        XCTAssertEqual(migrated.tuning.pinchOpenRatio, 0.34)
        XCTAssertEqual(migrated.tuning.pinchIntentRatio, 0.42, accuracy: 1e-12)
        XCTAssertEqual(migrated.tuning.quickPinchMaximumDuration, 0.27)
        XCTAssertEqual(migrated.tuning.pinchMotionActivationDisplacement, 0.07)
        XCTAssertEqual(migrated.tuning.zoomSensitivity, 1.5)
    }

    func testInvalidSettingsFallBackAtomicallyRatherThanPartiallyRepairing() throws {
        let suiteName = "com.allenxu.SignalTests.invalid.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var validCustom = GestureTuning.safeDefaults
        validCustom.pointerSensitivity = 500
        XCTAssertTrue(store.setTuning(validCustom))

        var invalid = validCustom
        invalid.pinchCloseRatio = invalid.pinchOpenRatio
        XCTAssertFalse(store.setTuning(invalid))
        XCTAssertEqual(store.tuning, .safeDefaults)
        XCTAssertNotNil(store.lastValidationMessage)

        invalid = validCustom
        invalid.trackingLossGraceDuration = 0.151
        XCTAssertFalse(store.setTuning(invalid))
        XCTAssertEqual(store.tuning, .safeDefaults)

        invalid = validCustom
        invalid.pointerSensitivity = .nan
        XCTAssertFalse(store.setTuning(invalid))
        XCTAssertEqual(store.tuning, .safeDefaults)

        invalid = validCustom
        invalid.pinchScrollActivationDisplacement = 0
        XCTAssertFalse(store.setTuning(invalid))
        invalid = validCustom
        invalid.quickPinchMaximumDuration = -0.001
        XCTAssertFalse(store.setTuning(invalid))
        invalid = validCustom
        invalid.oneEuroMinimumCutoff = 0
        XCTAssertFalse(store.setTuning(invalid))
        invalid = validCustom
        invalid.zoomMaximumStepsPerFrame = .max
        XCTAssertFalse(store.setTuning(invalid))
        invalid = validCustom
        invalid.scrollSensitivityY = .infinity
        XCTAssertFalse(store.setTuning(invalid))
    }

    func testFreshAppStateNeverRestoresEnabledIntent() throws {
        let state = AppState()
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .disabled)

        let suiteName = "com.allenxu.SignalTests.tamper.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ControlIntent.enabled.rawValue, forKey: "controlIntent")

        let freshState = AppState()
        XCTAssertEqual(freshState.controlIntent, .disabled)
        XCTAssertEqual(freshState.status, .disabled)
    }

    func testTransientRecognitionGapWaitsWithoutClearingExplicitIntent() {
        let state = AppState()
        let input = makeInputController()
        let coordinator = AppCoordinator(state: state, inputController: input)
        input.setOutputGate(enabled: true)
        _ = input.snapshot()
        XCTAssertTrue(input.snapshot().outputEnabled)
        state.apply(controlIntent: .enabled, status: .enabled)

        coordinator.handleTracking(
            snapshot: TrackingSnapshot(
                timestamp: .init(rawValue: 1),
                hands: [],
                quality: .degraded,
                degradationReason: .lowRequiredJointConfidence
            ),
            gesture: GestureFrameResult(
                poses: [],
                events: [],
                stateDescription: "transient confidence grace",
                diagnostics: GestureDiagnostics(
                    activeGesture: .pendingClick,
                    degradationReason: .lowRequiredJointConfidence
                )
            )
        )

        XCTAssertEqual(state.controlIntent, .enabled)
        XCTAssertEqual(state.status, .waitingForHand)
        XCTAssertTrue(input.snapshot().outputEnabled)
    }

    func testFreshNoHandFrameWaitsWithoutClearingExplicitIntent() {
        let state = AppState()
        let input = makeInputController()
        let coordinator = AppCoordinator(state: state, inputController: input)
        input.setOutputGate(enabled: true)
        _ = input.snapshot()
        state.apply(controlIntent: .enabled, status: .enabled)

        coordinator.handleTracking(
            snapshot: TrackingSnapshot(
                timestamp: .init(rawValue: 1),
                hands: [],
                quality: .absent,
                degradationReason: .noHandDetected
            ),
            gesture: GestureFrameResult(
                poses: [],
                events: [],
                stateDescription: "no hand",
                diagnostics: GestureDiagnostics(
                    degradationReason: .noHandDetected,
                    pointerSuppressionReason: .trackingUnavailable
                )
            )
        )

        XCTAssertEqual(state.controlIntent, .enabled)
        XCTAssertEqual(state.status, .waitingForHand)
        XCTAssertTrue(input.snapshot().outputEnabled)
    }

    func testWaitingForHandStatusIsNeutralAndExplainsControlRemainsEnabled() {
        let state = AppState()
        state.apply(controlIntent: .enabled, status: .waitingForHand)
        XCTAssertEqual(state.statusText, "Control enabled — waiting for a clear hand")

        let model = SignalUIModel(
            controlIntent: .enabled,
            status: .waitingForHand,
            cameraAuthorized: true,
            accessibilityTrusted: true
        )
        XCTAssertEqual(model.statusText, "Control enabled — waiting for a clear hand")
        XCTAssertFalse(model.statusIsWarning)
    }

    func testPoseMismatchWaitsWithoutEndingEnabledSession() {
        let state = AppState()
        let input = makeInputController()
        let coordinator = AppCoordinator(state: state, inputController: input)
        input.setOutputGate(enabled: true)
        _ = input.snapshot()
        state.apply(controlIntent: .enabled, status: .enabled)

        coordinator.handleTracking(
            snapshot: TrackingSnapshot(
                timestamp: .init(rawValue: 1),
                hands: [SyntheticHand.pose(.openPalm).tracked(at: 1)],
                quality: .good
            ),
            gesture: GestureFrameResult(
                poses: [],
                events: [],
                stateDescription: "unsupported pose",
                diagnostics: GestureDiagnostics(pointerSuppressionReason: .poseMismatch)
            )
        )

        XCTAssertEqual(state.controlIntent, .enabled)
        XCTAssertEqual(state.status, .waitingForHand)
        XCTAssertTrue(input.snapshot().outputEnabled)
    }

    func testEnableAgainstAlreadyRunningCameraArmsFirstSnapshotWatchdog() async {
        let clock = LockedCoordinatorClock(30)
        let watchdog = TrackingLossWatchdog(now: { clock.value })
        let state = AppState()
        let input = makeInputController()
        let recorder = OrderedCallRecorder()
        let coordinator = AppCoordinator(
            state: state,
            cameraController: CameraControllerSpy(recorder: recorder),
            inputController: input,
            trackingWatchdog: watchdog,
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: true
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: true,
                localMonitorInstalled: true
            )
        )
        coordinator.startRuntime()
        // Calibration or startup may already have the camera running before
        // the user explicitly enables Control.
        coordinator.handleCameraState(.init(
            revision: 1,
            state: .running(generation: 77, deviceName: "Test Camera")
        ))
        coordinator.enableControl()
        XCTAssertEqual(state.controlIntent, .enabled)
        XCTAssertEqual(state.status, .waitingForHand)

        XCTAssertFalse(watchdog.check(now: 31.9999))
        XCTAssertTrue(watchdog.check(now: 32.0000))
        XCTAssertFalse(input.snapshot().outputEnabled)

        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .trackingDegraded)
    }

    func testEnableControlClearsLatentGestureStateBeforeWaitingForHand() {
        let recorder = OrderedCallRecorder()
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            gestureResetter: GestureResetSpy(
                recorder: recorder,
                terminalEvents: [.dragEnd]
            ),
            inputController: InputControllerSpy(recorder: recorder),
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: true
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: true,
                localMonitorInstalled: true
            )
        )
        recorder.calls.removeAll()

        coordinator.enableControl()

        XCTAssertEqual(
            Array(recorder.calls.prefix(4)),
            [
                "input.gate(false)",
                "gesture.reset(paused)",
                "input.handle(dragEnd)",
                "input.release"
            ]
        )
        XCTAssertEqual(state.mode, .control)
        XCTAssertEqual(state.controlIntent, .enabled)
        XCTAssertEqual(state.status, .waitingForHand)
    }

    func testCommandsFailClosedWhenEmergencyMonitorIsUnavailable() {
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: true
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: false,
                localMonitorInstalled: true
            ),
            commandRecognitionRuntime: SignalCommandRecognitionRuntime()
        )

        coordinator.setMode(.commands)

        XCTAssertEqual(state.mode, .paused)
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .emergencyStopped)
    }

    func testCommandsRequireAccessibilityEvenWithLocalEmergencyMonitor() {
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: false
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: false,
                localMonitorInstalled: true
            ),
            commandRecognitionRuntime: SignalCommandRecognitionRuntime()
        )

        coordinator.setMode(.commands)

        XCTAssertEqual(state.mode, .paused)
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .accessibilityPermissionMissing)
    }

    func testEmergencyStopSynchronouslyCancelsTeachByDemoCapture() {
        var cancellations = 0
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            cancelTeachByDemoCapture: {
                cancellations += 1
            }
        )
        state.setMode(.commands)

        coordinator.emergencyStop()

        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(state.mode, .paused)
        XCTAssertEqual(state.status, .emergencyStopped)
    }

    func testStartupTimeoutReenableAcceptsLowerNewGenerationTimestamp() async {
        let clock = LockedCoordinatorClock(100)
        let watchdog = TrackingLossWatchdog(now: { clock.value })
        let state = AppState()
        let input = makeInputController()
        let pipeline = GesturePipeline(tuning: .safeDefaults, inputSink: input)
        let coordinator = AppCoordinator(
            state: state,
            cameraController: CameraControllerSpy(recorder: OrderedCallRecorder()),
            gestureResetter: pipeline,
            inputController: input,
            trackingWatchdog: watchdog,
            initialPermissions: PermissionSnapshot(
                camera: .authorized,
                accessibilityTrusted: true
            ),
            initialEmergencyHealth: EmergencyMonitorHealth(
                globalMonitorInstalled: true,
                localMonitorInstalled: true
            )
        )
        coordinator.startRuntime()
        coordinator.handleCameraState(.init(
            revision: 1,
            state: .running(generation: 70, deviceName: "Test Camera")
        ))
        coordinator.enableControl()
        XCTAssertTrue(watchdog.check(now: 102))
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(state.controlIntent, .disabled)

        coordinator.enableControl()
        coordinator.handleCameraState(.init(
            revision: 2,
            state: .running(generation: 71, deviceName: "Test Camera")
        ))
        var recovered = trackingFrame(
            time: 1,
            hands: [SyntheticHand.pose(.pointer).tracked(at: 1)]
        )
        recovered.captureGeneration = 71
        let result = pipeline.process(recovered)

        XCTAssertNotEqual(result.diagnostics.degradationReason, .invalidTimestamp)
        XCTAssertNotEqual(result.diagnostics.pointerSuppressionReason, .trackingUnavailable)
    }

    func testGenuineTrackingLossClosesGateAndRequiresExplicitReenable() {
        let state = AppState()
        let input = makeInputController()
        let coordinator = AppCoordinator(state: state, inputController: input)
        input.setOutputGate(enabled: true)
        _ = input.snapshot()
        XCTAssertTrue(input.snapshot().outputEnabled)
        state.apply(controlIntent: .enabled, status: .enabled)

        coordinator.handleTracking(
            snapshot: TrackingSnapshot(
                timestamp: .init(rawValue: 2),
                hands: [],
                quality: .absent,
                degradationReason: .noHandDetected
            ),
            gesture: GestureFrameResult(
                poses: [],
                events: [.trackingLost],
                stateDescription: "tracking lost",
                diagnostics: GestureDiagnostics(degradationReason: .noHandDetected)
            )
        )

        XCTAssertFalse(input.snapshot().outputEnabled)
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .trackingDegraded)

        coordinator.handleTracking(
            snapshot: TrackingSnapshot(
                timestamp: .init(rawValue: 2.1),
                hands: [],
                quality: .good
            ),
            gesture: GestureFrameResult(poses: [], events: [], stateDescription: "recovered")
        )
        XCTAssertFalse(input.snapshot().outputEnabled)
        XCTAssertEqual(state.controlIntent, .disabled)
    }

    func testCalibrationDiagnosticsExposeTypedGestureAndTrackingReason() async {
        let viewModel = CalibrationViewModel(overlayRate: 1_000, diagnosticsRate: 1_000)
        let gestureDiagnostics = GestureDiagnostics(
            recognizedPose: .pinch,
            pendingClick: false,
            activeGesture: .scroll,
            pinchDuration: 0.12,
            scrollDisplacement: 0.03,
            scrollDelta: -0.01,
            requiredJointConfidence: 0.72,
            zoomDistance: 1.4,
            zoomDelta: 0.02,
            middleThumbNormalizedDistance: 0.205,
            pointerSuppressionReason: .scrolling,
            scrollAnchor: Point2D(x: 0.42, y: 0.61),
            scrollVerticalDelta: -0.04,
            fistRejectionReason: .activePinchEpisode
        )
        viewModel.submit(
            tracking: TrackingSnapshot(
                timestamp: .init(rawValue: 3),
                hands: [],
                quality: .degraded,
                degradationReason: .associationAmbiguous
            ),
            gesture: GestureFrameResult(
                poses: [],
                events: [],
                stateDescription: "scrolling",
                diagnostics: gestureDiagnostics
            ),
            input: .zero,
            permissions: .init(cameraAuthorized: true, accessibilityTrusted: true),
            inputEnabled: false
        )
        await Task.yield()

        XCTAssertEqual(viewModel.diagnostics.gesture.recognizedPose, .pinch)
        XCTAssertEqual(viewModel.diagnostics.gesture.activeGesture, .scroll)
        XCTAssertFalse(viewModel.diagnostics.gesture.pendingClick)
        XCTAssertEqual(viewModel.diagnostics.gesture.middleThumbNormalizedDistance, 0.205)
        XCTAssertEqual(viewModel.diagnostics.gesture.pointerSuppressionReason, .scrolling)
        XCTAssertEqual(viewModel.diagnostics.gesture.pinchDuration, 0.12)
        XCTAssertEqual(viewModel.diagnostics.gesture.scrollAnchor, Point2D(x: 0.42, y: 0.61))
        XCTAssertEqual(viewModel.diagnostics.gesture.scrollVerticalDelta, -0.04)
        XCTAssertEqual(viewModel.diagnostics.gesture.fistRejectionReason, .activePinchEpisode)
        XCTAssertEqual(viewModel.diagnostics.gesture.requiredJointConfidence, 0.72)
        XCTAssertEqual(
            viewModel.diagnostics.gesture.degradationReason,
            .associationAmbiguous
        )
    }

    func testPauseDuringDragClosesGateForwardsDragEndThenReleases() {
        let recorder = OrderedCallRecorder()
        let state = AppState()
        let camera = CameraControllerSpy(recorder: recorder)
        let gestures = GestureResetSpy(recorder: recorder, terminalEvents: [.dragEnd])
        let input = InputControllerSpy(recorder: recorder)
        let coordinator = AppCoordinator(
            state: state,
            cameraController: camera,
            gestureResetter: gestures,
            inputController: input
        )
        recorder.calls.removeAll()

        coordinator.quiesce(reason: .paused)

        XCTAssertEqual(recorder.calls, [
            "input.gate(false)",
            "gesture.reset(paused)",
            "input.handle(dragEnd)",
            "input.release",
            "camera.stop"
        ])
        XCTAssertEqual(state.controlIntent, .paused)
        XCTAssertEqual(state.status, .paused)
    }

    func testDisableDuringDragReleasesBeforeCameraStop() {
        let recorder = OrderedCallRecorder()
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            cameraController: CameraControllerSpy(recorder: recorder),
            gestureResetter: GestureResetSpy(recorder: recorder, terminalEvents: [.dragEnd]),
            inputController: InputControllerSpy(recorder: recorder)
        )
        recorder.calls.removeAll()

        coordinator.quiesce(reason: .userDisabled)

        XCTAssertEqual(recorder.calls, [
            "input.gate(false)",
            "gesture.reset(disabled)",
            "input.handle(dragEnd)",
            "input.release",
            "camera.stop"
        ])
        XCTAssertLessThan(
            try! XCTUnwrap(recorder.calls.firstIndex(of: "input.release")),
            try! XCTUnwrap(recorder.calls.firstIndex(of: "camera.stop"))
        )
        XCTAssertEqual(state.controlIntent, .disabled)
        XCTAssertEqual(state.status, .disabled)
    }

    func testCalibrationKeepsCameraPolicyButNeverSkipsReleaseFence() {
        let recorder = OrderedCallRecorder()
        let state = AppState()
        state.setCalibrationOpen(true)
        let coordinator = AppCoordinator(
            state: state,
            cameraController: CameraControllerSpy(recorder: recorder),
            gestureResetter: GestureResetSpy(recorder: recorder),
            inputController: InputControllerSpy(recorder: recorder)
        )
        recorder.calls.removeAll()

        coordinator.quiesce(reason: .trackingLost)
        XCTAssertEqual(recorder.calls, [
            "input.gate(false)",
            "gesture.reset(trackingLost)",
            "input.release"
        ])
        XCTAssertEqual(state.status, .trackingDegraded)
    }

    func testCoordinatorMapsPermissionEmergencyDisplayAndShutdownReasons() {
        let cases: [(SafetyStopReason, GestureResetReason, AppStatus)] = [
            (.cameraPermissionLost, .permissionLost, .cameraPermissionMissing),
            (.accessibilityPermissionLost, .permissionLost, .accessibilityPermissionMissing),
            (.emergency, .emergency, .emergencyStopped),
            (.displayConfigurationChanged, .displayConfigurationChanged, .disabled),
            (.shutdown, .shutdown, .disabled)
        ]

        for (reason, resetReason, status) in cases {
            let recorder = OrderedCallRecorder()
            let state = AppState()
            let coordinator = AppCoordinator(
                state: state,
                cameraController: CameraControllerSpy(recorder: recorder),
                gestureResetter: GestureResetSpy(recorder: recorder),
                inputController: InputControllerSpy(recorder: recorder)
            )
            recorder.calls.removeAll()
            coordinator.quiesce(reason: reason)

            XCTAssertEqual(recorder.calls.first, "input.gate(false)")
            XCTAssertEqual(recorder.calls.dropFirst().first, "gesture.reset(\(resetReason.rawValue))")
            XCTAssertTrue(recorder.calls.contains("input.release"))
            XCTAssertEqual(state.status, status)
        }
    }

    func testLifecycleSignalSafetyAndRecoveryMappings() {
        XCTAssertEqual(AppLifecycleSignal.willSleep.safetyStopReason, .sleep)
        XCTAssertEqual(AppLifecycleSignal.screensDidSleep.safetyStopReason, .sleep)
        XCTAssertEqual(AppLifecycleSignal.sessionDidResignActive.safetyStopReason, .sessionInactive)
        XCTAssertEqual(AppLifecycleSignal.applicationWillTerminate.safetyStopReason, .shutdown)
        XCTAssertEqual(
            AppLifecycleSignal.displayConfigurationChanged.safetyStopReason,
            .displayConfigurationChanged
        )

        for signal in [
            AppLifecycleSignal.didWake,
            .screensDidWake,
            .sessionDidBecomeActive,
            .applicationDidBecomeActive
        ] {
            XCTAssertNil(signal.safetyStopReason)
            XCTAssertTrue(signal.requestsStatusRefresh)
        }
    }

    private func makeInputController() -> MacOSInputController {
        MacOSInputController(
            backend: FakeInputBackend(),
            trustProvider: FakeInputTrustProvider(),
            applicationProvider: FakeFrontmostApplicationProvider(),
            clock: FakeInputClock()
        )
    }

    private func settingsDataWithoutScrollStabilization(_ data: Data) throws -> Data {
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var tuning = try XCTUnwrap(root["tuning"] as? [String: Any])
        XCTAssertNotNil(tuning.removeValue(forKey: "scrollStabilizationFramesStorage"))
        root["tuning"] = tuning
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func settingsDataWithoutScreenZoomConfirmation(_ data: Data) throws -> Data {
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(root.removeValue(forKey: "screenZoomShortcutsEnabled"))
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func settingsDataWithoutOneHandAxisVersion(_ data: Data) throws -> Data {
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var tuning = try XCTUnwrap(root["tuning"] as? [String: Any])
        XCTAssertNotNil(tuning.removeValue(forKey: "oneHandAxisMappingVersionStorage"))
        tuning.removeValue(forKey: "pinchIntentRatioStorage")
        root["tuning"] = tuning
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func settingsData(
        _ data: Data,
        withOneHandAxisVersion version: Int
    ) throws -> Data {
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var tuning = try XCTUnwrap(root["tuning"] as? [String: Any])
        tuning["oneHandAxisMappingVersionStorage"] = version
        root["tuning"] = tuning
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

private final class LaunchAtLoginControllerSpy: LaunchAtLoginControlling {
    var enabled = false
    var approvalRequired = false
    private(set) var enabledReadCount = 0
    private(set) var approvalReadCount = 0
    private(set) var setEnabledRequests: [Bool] = []
    private(set) var openSettingsCount = 0

    var statusReadCount: Int {
        enabledReadCount + approvalReadCount
    }

    var isEnabled: Bool {
        enabledReadCount += 1
        return enabled
    }

    var requiresApproval: Bool {
        approvalReadCount += 1
        return approvalRequired
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledRequests.append(enabled)
        self.enabled = enabled
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

private final class OrderedCallRecorder {
    var calls: [String] = []
}

private final class LockedCoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double

    init(_ value: Double) { storedValue = value }

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

private final class CameraControllerSpy: CameraControlling {
    private let recorder: OrderedCallRecorder

    init(recorder: OrderedCallRecorder) {
        self.recorder = recorder
    }

    func start() { recorder.calls.append("camera.start") }
    func stop() { recorder.calls.append("camera.stop") }
}

private final class GestureResetSpy: GestureResetting {
    private let recorder: OrderedCallRecorder
    private let terminalEvents: [GestureEvent]

    init(recorder: OrderedCallRecorder, terminalEvents: [GestureEvent] = []) {
        self.recorder = recorder
        self.terminalEvents = terminalEvents
    }

    func reset(reason: GestureResetReason) -> [GestureEvent] {
        recorder.calls.append("gesture.reset(\(reason.rawValue))")
        return terminalEvents
    }
}

private final class InputControllerSpy: InputControlling {
    private let recorder: OrderedCallRecorder

    init(recorder: OrderedCallRecorder) {
        self.recorder = recorder
    }

    func setOutputGate(enabled: Bool) {
        recorder.calls.append("input.gate(\(enabled))")
    }

    func handle(_ event: GestureEvent) {
        recorder.calls.append("input.handle(\(event.label))")
    }

    func releaseAllInputs() {
        recorder.calls.append("input.release")
    }
}

private extension GestureEvent {
    var label: String {
        switch self {
        case .pointerDelta: "pointerDelta"
        case .leftClick: "leftClick"
        case .doubleClick: "doubleClick"
        case .dragStart: "dragStart"
        case .dragDelta: "dragDelta"
        case .dragEnd: "dragEnd"
        case .rightClick: "rightClick"
        case .scroll: "scroll"
        case .zoom: "zoom"
        case .trackingLost: "trackingLost"
        }
    }
}
