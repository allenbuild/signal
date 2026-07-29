import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalDashboardPresentationTests: XCTestCase {
    func testModesAreExactlyPausedControlAndCommands() {
        XCTAssertEqual(
            SignalDashboardMode.allCases.map(\.title),
            ["Paused", "Control", "Commands"]
        )
    }

    func testCanonicalCardsAreExactlyTheFixedTwoByFourCatalog() {
        let cards = SignalDashboardPresentation().cards

        XCTAssertEqual(cards.count, 8)
        XCTAssertEqual(
            cards.map { "\($0.gestureLabel)|\($0.commandName)" },
            [
                "One|Rickroll",
                "Two|New Gmail",
                "Three|Cursor Agents",
                "Four|New Google Doc",
                "Thumbs Up|Build with Bolt",
                "Thumbs Down|Next Spotify Track",
                "C|Anthropic on X",
                "Fist|Custom Command",
            ]
        )
        XCTAssertFalse(
            cards.contains {
                $0.gestureLabel.localizedCaseInsensitiveCompare("Five")
                    == .orderedSame
            }
        )
    }

    func testSuppliedCardsCannotChangeCardCountOrCanonicalOrder() {
        let customFist = SignalDashboardCommandCard(
            id: .fist,
            gestureLabel: "Fist",
            commandName: "My Reviewed Macro",
            symbolName: "hand.raised.fill"
        )
        let presentation = SignalDashboardPresentation(
            cards: [customFist, customFist]
        )

        XCTAssertEqual(
            presentation.cards.map(\.id),
            SignalDashboardCardID.allCases
        )
        XCTAssertEqual(presentation.cards.count, 8)
        XCTAssertEqual(
            presentation.cards.last?.commandName,
            "My Reviewed Macro"
        )
    }

    func testActivationAndTelemetryValuesAreClampedForPresentation() {
        var presentation = SignalDashboardPresentation(
            telemetry: .init(
                confidence: 2,
                captureFPS: -.infinity,
                processedFPS: -5,
                visionLatencyMilliseconds: .nan,
                endToEndLatencyMilliseconds: 8
            ),
            activeCardID: .one,
            activationProgress: -1
        )

        XCTAssertEqual(presentation.activationProgress, 0)
        XCTAssertEqual(presentation.telemetry.confidence, 1)
        XCTAssertEqual(presentation.telemetry.captureFPS, 0)
        XCTAssertEqual(presentation.telemetry.processedFPS, 0)
        XCTAssertEqual(presentation.telemetry.visionLatencyMilliseconds, 0)
        XCTAssertEqual(presentation.telemetry.endToEndLatencyMilliseconds, 8)

        presentation.setActivation(cardID: .two, progress: 4)
        XCTAssertEqual(presentation.activeCardID, .two)
        XCTAssertEqual(presentation.activationProgress, 1)
    }

    func testActivityLogIsNewestFirstAndBounded() {
        var presentation = SignalDashboardPresentation()
        for index in 0..<(SignalDashboardPresentation.maximumActivityItems + 12) {
            presentation.recordActivity(
                SignalDashboardActivity(
                    id: "\(index)",
                    timestamp: Date(timeIntervalSince1970: Double(index)),
                    title: "Activity \(index)"
                )
            )
        }

        XCTAssertEqual(
            presentation.activity.count,
            SignalDashboardPresentation.maximumActivityItems
        )
        XCTAssertEqual(presentation.activity.first?.id, "111")
        XCTAssertEqual(presentation.activity.last?.id, "12")
    }

    func testConstructionDoesNotInvokeAnyAction() {
        let recorder = DashboardActionRecorder()
        let actions = SignalDashboardActions(
            selectMode: { _ in recorder.record() },
            editCommand: { _ in recorder.record() },
            requestPermission: { _ in recorder.record() },
            openCalibration: { recorder.record() },
            openSettings: { recorder.record() },
            emergencyStop: { recorder.record() }
        )

        _ = SignalDashboardView(
            presentation: SignalDashboardPresentation(),
            actions: actions
        )

        XCTAssertEqual(recorder.invocationCount, 0)
    }

    func testOptionalPermissionsRemainSeparatedFromCorePermissions() {
        let model = SignalUIModel()
        model.apply(
            controlIntent: .disabled,
            status: .paused,
            cameraAuthorized: true,
            cameraPermission: .authorized,
            accessibilityTrusted: true,
            calibrationIsOpen: false,
            mode: .paused
        )
        model.updateOptionalPermissions(
            .init(browserAutomation: .denied, screenRecording: .unavailable)
        )

        func state(
            _ kind: SignalDashboardPermissionKind
        ) -> SignalDashboardPermissionState? {
            model.dashboardPresentation.permissions.first {
                $0.kind == kind
            }?.state
        }
        XCTAssertEqual(state(.camera), .granted)
        XCTAssertEqual(state(.accessibility), .granted)
        XCTAssertEqual(state(.browserAutomation), .denied)
        XCTAssertEqual(state(.screenRecording), .notRequired)
    }

    func testOptionalPermissionConstructionDoesNotRecordPromptAttempts() {
        let suite = "SignalDashboardPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = OptionalPermissionService(defaults: defaults)

        XCTAssertFalse(
            defaults.bool(forKey: "Signal.permissions.chromeAutomationPrompted")
        )
        XCTAssertFalse(
            defaults.bool(forKey: "Signal.permissions.screenRecordingPrompted")
        )
    }
}

@MainActor
private final class DashboardActionRecorder {
    private(set) var invocationCount = 0

    func record() {
        invocationCount += 1
    }
}
