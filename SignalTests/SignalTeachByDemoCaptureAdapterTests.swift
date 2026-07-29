import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalTeachByDemoCaptureAdapterTests: XCTestCase {
    func testConstructionDoesNotStartAnyCaptureSource() {
        let harness = CaptureHarness()

        _ = harness.makeAdapter()

        XCTAssertEqual(harness.events.startCount, 0)
        XCTAssertEqual(harness.applications.startCount, 0)
        XCTAssertEqual(harness.scheduler.startCount, 0)
        XCTAssertEqual(harness.preview.startCount, 0)
        XCTAssertEqual(harness.proposals.beginCount, 0)
    }

    func testExplicitStartPublishesVisibleRecordingState() throws {
        let harness = CaptureHarness()
        harness.clock.now = 10
        let adapter = harness.makeAdapter()
        var states: [SignalTeachByDemoCaptureVisibleState] = []
        adapter.onVisibleStateChange = { states.append($0) }

        try adapter.start()

        XCTAssertTrue(adapter.isRecording)
        XCTAssertEqual(harness.events.startCount, 1)
        XCTAssertEqual(harness.applications.startCount, 1)
        XCTAssertEqual(harness.scheduler.startCount, 1)
        XCTAssertEqual(harness.preview.startCount, 1)
        XCTAssertEqual(harness.proposals.beginCount, 1)
        XCTAssertEqual(states.last?.phase, .recording)
        XCTAssertEqual(states.last?.elapsed, 0)
    }

    func testRecommendedDurationIsVisibleAndSixtySecondsHardStops() throws {
        let harness = CaptureHarness()
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.clock.now = 29.9
        harness.scheduler.fire()
        XCTAssertFalse(adapter.visibleState.hasReachedRecommendedDuration)
        XCTAssertTrue(adapter.isRecording)

        harness.clock.now = 30
        harness.scheduler.fire()
        XCTAssertTrue(adapter.visibleState.hasReachedRecommendedDuration)
        XCTAssertTrue(adapter.isRecording)

        harness.clock.now = 60
        harness.scheduler.fire()
        XCTAssertFalse(adapter.isRecording)
        XCTAssertEqual(adapter.visibleState.phase, .stopped)
        XCTAssertEqual(adapter.visibleState.elapsed, 60)
        XCTAssertEqual(adapter.visibleState.stopReason, .durationLimit)
        XCTAssertEqual(harness.proposals.finishCount, 1)
        XCTAssertEqual(harness.events.stopCount, 1)
        XCTAssertEqual(harness.applications.stopCount, 1)
        XCTAssertEqual(harness.preview.stopCount, 1)
    }

    func testEmergencyCancellationIsImmediateAndDoesNotEnterReview() throws {
        let harness = CaptureHarness()
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.clock.now = 4
        adapter.emergencyCancel()

        XCTAssertEqual(adapter.visibleState.phase, .cancelled)
        XCTAssertEqual(adapter.visibleState.stopReason, .emergency)
        XCTAssertEqual(harness.proposals.cancelCount, 1)
        XCTAssertEqual(harness.proposals.finishCount, 0)
        XCTAssertNil(harness.events.handler)
        XCTAssertNil(harness.applications.handler)
        XCTAssertNil(harness.scheduler.handler)
    }

    func testPointerRequiresReviewedApplicationAndReviewedAXTarget()
        async throws
    {
        let app = SignalTeachByDemoApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.App",
            localizedName: "Example"
        )
        let harness = CaptureHarness(frontmostApplication: app)
        let target = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: app.bundleIdentifier,
            role: "AXButton",
            title: "Continue",
            identifier: "continue",
            wasUserReviewed: false
        )
        harness.resolver.reviewedApplications = [app.bundleIdentifier]
        harness.resolver.pointerTarget = .init(
            target: target,
            isReviewed: false
        )
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.events.emit(
            .primaryPointerReleased(at: .init(x: 120, y: 240))
        )
        await Task.yield()
        XCTAssertTrue(harness.proposals.clickTargets.isEmpty)

        harness.resolver.pointerTarget = .init(
            target: target,
            isReviewed: true
        )
        harness.events.emit(
            .primaryPointerReleased(at: .init(x: 900, y: 400))
        )
        await Task.yield()

        XCTAssertEqual(harness.proposals.clickTargets.count, 1)
        XCTAssertEqual(
            harness.proposals.clickTargets.first?.identifier,
            "continue"
        )
        XCTAssertTrue(
            harness.proposals.clickTargets.first?.wasUserReviewed == true
        )
    }

    func testKeyboardCreatesOnlyHighLevelTextOrComboForReviewedTarget()
        async throws
    {
        let app = SignalTeachByDemoApplication(
            processIdentifier: 7,
            bundleIdentifier: "com.example.Editor",
            localizedName: "Editor"
        )
        let harness = CaptureHarness(frontmostApplication: app)
        let target = SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: app.bundleIdentifier,
            role: "AXTextField",
            title: "Search",
            identifier: "search",
            wasUserReviewed: false
        )
        harness.resolver.reviewedApplications = [app.bundleIdentifier]
        harness.resolver.focused = .init(
            target: target,
            isReviewed: true
        )
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.events.emit(
            .keyDown(
                keyCode: 0,
                text: "a",
                modifiers: [.shift],
                isRepeat: false
            )
        )
        await Task.yield()
        harness.events.emit(
            .keyDown(
                keyCode: 40,
                text: "k",
                modifiers: [.command],
                isRepeat: false
            )
        )
        await Task.yield()
        harness.events.emit(
            .keyDown(
                keyCode: 40,
                text: "k",
                modifiers: [.command],
                isRepeat: true
            )
        )
        await Task.yield()

        XCTAssertEqual(harness.proposals.typedTexts, ["a"])
        XCTAssertEqual(
            harness.proposals.keyCombos,
            [.init(key: "k", modifiers: [.command])]
        )
    }

    func testSecureInputAndSecureAXTargetEmitOnlyRedactionCount()
        async throws
    {
        let app = SignalTeachByDemoApplication(
            processIdentifier: 9,
            bundleIdentifier: "com.example.Login",
            localizedName: "Login"
        )
        let harness = CaptureHarness(frontmostApplication: app)
        harness.resolver.reviewedApplications = [app.bundleIdentifier]
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.events.emit(.secureKeyboardInput)
        await Task.yield()
        harness.resolver.focused = .init(
            target: .init(
                applicationBundleIdentifier: app.bundleIdentifier,
                role: "AXSecureTextField",
                title: "Secure field",
                isSecureField: true,
                wasUserReviewed: false
            ),
            isReviewed: false
        )
        harness.events.emit(
            .keyDown(
                keyCode: 0,
                text: "never-retain-this",
                modifiers: [],
                isRepeat: false
            )
        )
        await Task.yield()

        XCTAssertEqual(adapter.visibleState.redactionCount, 2)
        XCTAssertEqual(harness.proposals.redactionCount, 2)
        XCTAssertTrue(harness.proposals.typedTexts.isEmpty)
        XCTAssertTrue(harness.proposals.keyCombos.isEmpty)
        XCTAssertTrue(harness.proposals.clickTargets.isEmpty)
    }

    func testSecretLikeTextIsRedactedOnceWithoutRetention() async throws {
        let app = SignalTeachByDemoApplication(
            processIdentifier: 10,
            bundleIdentifier: "com.example.Form",
            localizedName: "Form"
        )
        let harness = CaptureHarness(frontmostApplication: app)
        harness.resolver.reviewedApplications = [app.bundleIdentifier]
        harness.resolver.focused = .init(
            target: .init(
                applicationBundleIdentifier: app.bundleIdentifier,
                role: "AXTextField",
                title: "Notes",
                wasUserReviewed: false
            ),
            isReviewed: true
        )
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.events.emit(
            .keyDown(
                keyCode: 0,
                text: "password: do-not-retain",
                modifiers: [],
                isRepeat: false
            )
        )
        await Task.yield()

        XCTAssertEqual(adapter.visibleState.redactionCount, 1)
        XCTAssertEqual(harness.proposals.redactionCount, 1)
        XCTAssertTrue(harness.proposals.typedTexts.isEmpty)
    }

    func testActivationCreatesURLProposalOnlyForReviewedAppAndURL()
        throws
    {
        let initial = SignalTeachByDemoApplication(
            processIdentifier: 1,
            bundleIdentifier: "com.example.Initial",
            localizedName: "Initial"
        )
        let reviewed = SignalTeachByDemoApplication(
            processIdentifier: 2,
            bundleIdentifier: "com.example.Browser",
            localizedName: "Browser"
        )
        let ignored = SignalTeachByDemoApplication(
            processIdentifier: 3,
            bundleIdentifier: "com.example.Other",
            localizedName: "Other"
        )
        let harness = CaptureHarness(frontmostApplication: initial)
        harness.resolver.reviewedApplications = [reviewed.bundleIdentifier]
        harness.resolver.urls[reviewed.bundleIdentifier] =
            "https://example.com/reviewed"
        let adapter = harness.makeAdapter()
        try adapter.start()

        harness.applications.activate(ignored)
        harness.applications.activate(reviewed)

        XCTAssertEqual(
            harness.proposals.urls,
            ["https://example.com/reviewed"]
        )
    }

    func testStartFailureRollsBackAllSourcesAndProposalSession() {
        let harness = CaptureHarness()
        harness.events.startError =
            SignalTeachByDemoCaptureError.eventTapUnavailable
        let adapter = harness.makeAdapter()

        XCTAssertThrowsError(try adapter.start())
        XCTAssertFalse(adapter.isRecording)
        guard case .failed = adapter.visibleState.phase else {
            return XCTFail("Expected failed visible state")
        }
        XCTAssertEqual(adapter.visibleState.stopReason, .startFailed)
        XCTAssertEqual(harness.proposals.beginCount, 1)
        XCTAssertEqual(harness.proposals.cancelCount, 1)
        XCTAssertEqual(harness.applications.stopCount, 1)
        XCTAssertEqual(harness.preview.stopCount, 1)
    }

    func testReviewedWaitRequiresActiveCapture() throws {
        let app = SignalTeachByDemoApplication(
            processIdentifier: 12,
            bundleIdentifier: "com.example.Reviewed",
            localizedName: "Reviewed"
        )
        let harness = CaptureHarness(frontmostApplication: app)
        harness.resolver.reviewedApplications = [app.bundleIdentifier]
        let adapter = harness.makeAdapter()

        XCTAssertThrowsError(try adapter.recordReviewedWait(milliseconds: 500))
        try adapter.start()
        try adapter.recordReviewedWait(milliseconds: 500)
        XCTAssertEqual(harness.proposals.waits, [500])
    }
}

@MainActor
private final class CaptureHarness {
    let events = FakeEventCapture()
    let applications: FakeApplicationObserver
    let resolver = FakeContextResolver()
    let scheduler = FakeScheduler()
    let clock = FakeClock()
    let preview = FakePreview()
    let proposals = FakeProposalReceiver()

    init(frontmostApplication: SignalTeachByDemoApplication? = nil) {
        applications = FakeApplicationObserver(
            frontmostApplication: frontmostApplication
        )
    }

    func makeAdapter() -> SignalTeachByDemoCaptureAdapter {
        SignalTeachByDemoCaptureAdapter(
            eventCapture: events,
            applicationObserver: applications,
            contextResolver: resolver,
            scheduler: scheduler,
            clock: clock,
            preview: preview,
            proposals: proposals
        )
    }
}

@MainActor
private final class FakeEventCapture: SignalTeachByDemoEventCapturing {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    var handler:
        (@Sendable (SignalTeachByDemoCapturedEvent) -> Void)?

    func start(
        handler: @escaping @Sendable (SignalTeachByDemoCapturedEvent) -> Void
    ) throws {
        startCount += 1
        if let startError { throw startError }
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func emit(_ event: SignalTeachByDemoCapturedEvent) {
        handler?(event)
    }
}

@MainActor
private final class FakeApplicationObserver:
    SignalTeachByDemoApplicationObserving
{
    var frontmostApplication: SignalTeachByDemoApplication?
    var startCount = 0
    var stopCount = 0
    var handler:
        (@MainActor (SignalTeachByDemoApplication) -> Void)?

    init(frontmostApplication: SignalTeachByDemoApplication?) {
        self.frontmostApplication = frontmostApplication
    }

    func start(
        handler: @escaping @MainActor (SignalTeachByDemoApplication) -> Void
    ) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func activate(_ application: SignalTeachByDemoApplication) {
        frontmostApplication = application
        handler?(application)
    }
}

@MainActor
private final class FakeContextResolver:
    SignalTeachByDemoContextResolving
{
    var reviewedApplications: Set<String> = []
    var pointerTarget: SignalTeachByDemoResolvedTarget?
    var focused: SignalTeachByDemoResolvedTarget?
    var urls: [String: String] = [:]

    func isApplicationReviewed(
        _ application: SignalTeachByDemoApplication
    ) -> Bool {
        reviewedApplications.contains(application.bundleIdentifier)
    }

    func target(
        at point: SignalTeachByDemoScreenPoint,
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget? {
        pointerTarget
    }

    func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalTeachByDemoResolvedTarget? {
        focused
    }

    func reviewedHTTPSURL(
        for application: SignalTeachByDemoApplication
    ) -> String? {
        urls[application.bundleIdentifier]
    }
}

@MainActor
private final class FakeScheduler:
    SignalTeachByDemoCaptureScheduling
{
    var startCount = 0
    var stopCount = 0
    var handler: (@MainActor () -> Void)?

    func startRepeating(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func fire() {
        handler?()
    }
}

@MainActor
private final class FakeClock: SignalTeachByDemoCaptureClock {
    var now: TimeInterval = 0
}

@MainActor
private final class FakePreview: SignalTeachByDemoLocalPreviewing {
    var startCount = 0
    var stopCount = 0

    func startLocalPreview() throws {
        startCount += 1
    }

    func stopLocalPreview() {
        stopCount += 1
    }
}

@MainActor
private final class FakeProposalReceiver:
    SignalTeachByDemoCaptureProposalReceiving
{
    var beginCount = 0
    var finishCount = 0
    var cancelCount = 0
    var redactionCount = 0
    var urls: [String] = []
    var clickTargets: [SignalReviewedAccessibilityTarget] = []
    var typedTexts: [String] = []
    var keyCombos: [SignalTeachByDemoKeyCombo] = []
    var waits: [Int] = []

    func beginCapture() {
        beginCount += 1
    }

    func finishCaptureForReview() throws {
        finishCount += 1
    }

    func cancel() {
        cancelCount += 1
    }

    func recordOpenHTTPSURL(_ rawURL: String) throws {
        urls.append(rawURL)
    }

    func recordAccessibilityClick(
        target: SignalReviewedAccessibilityTarget
    ) throws {
        clickTargets.append(target)
    }

    func recordTypedText(
        _ text: String,
        target: SignalReviewedAccessibilityTarget,
        isSecret: Bool
    ) throws {
        typedTexts.append(text)
    }

    func recordKeyCombo(_ combo: SignalTeachByDemoKeyCombo) throws {
        keyCombos.append(combo)
    }

    func recordWait(milliseconds: Int) throws {
        waits.append(milliseconds)
    }

    func recordSecureInputRedaction(
        applicationBundleIdentifier: String
    ) {
        redactionCount += 1
    }
}
