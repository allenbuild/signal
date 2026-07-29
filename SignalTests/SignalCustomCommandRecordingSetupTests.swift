import Foundation
import XCTest
@testable import Signal

@MainActor
final class SignalCustomCommandRecordingSetupTests: XCTestCase {
    func testInspectionDoesNotAuthorizeAndExplicitReviewUnlocksStart()
        throws
    {
        let application = makeApplication()
        let target = makeTarget()
        let inspector = FakeSetupInspector(
            application: application,
            target: target
        )
        let authorizer = FakeSetupAuthorizer()
        let model = SignalTeachByDemoRecordingSetupModel(
            inspector: inspector,
            authorizer: authorizer
        )

        XCTAssertEqual(inspector.inspections, 0)
        XCTAssertEqual(authorizer.authorizationCount, 0)
        XCTAssertFalse(model.isReadyToStart)

        model.inspectFrontmostContext()
        XCTAssertEqual(inspector.inspections, 2)
        XCTAssertEqual(authorizer.authorizationCount, 0)
        XCTAssertFalse(model.isReadyToStart)

        try model.authorizeCandidateApplication()
        XCTAssertEqual(authorizer.applications, ["com.example.Browser"])
        XCTAssertFalse(model.isReadyToStart)

        try model.authorizeCandidateTarget()
        XCTAssertEqual(authorizer.targets.count, 1)
        XCTAssertTrue(authorizer.targets[0].wasUserReviewed)
        XCTAssertTrue(model.isReadyToStart)

        model.reviewedURLText = "https://example.com/path"
        try model.authorizeHTTPSURL()
        XCTAssertEqual(
            authorizer.urls["com.example.Browser"],
            "https://example.com/path"
        )
    }

    func testSecureCandidateIsRedactedAndNeverAuthorized() throws {
        let secretTitle = "Password value hunter2"
        let secretIdentifier = "secret-password-input"
        let inspector = FakeSetupInspector(
            application: makeApplication(),
            target: SignalReviewedAccessibilityTarget(
                applicationBundleIdentifier: "com.example.Browser",
                role: "AXSecureTextField",
                title: secretTitle,
                identifier: secretIdentifier,
                isSecureField: true,
                wasUserReviewed: false
            )
        )
        let authorizer = FakeSetupAuthorizer()
        let model = SignalTeachByDemoRecordingSetupModel(
            inspector: inspector,
            authorizer: authorizer
        )

        model.inspectFrontmostContext()
        let candidate = try XCTUnwrap(model.candidateTarget)
        XCTAssertEqual(candidate.title, "Secure field")
        XCTAssertNil(candidate.identifier)
        XCTAssertFalse(candidate.title.contains(secretTitle))
        try model.authorizeCandidateApplication()
        XCTAssertThrowsError(try model.authorizeCandidateTarget()) {
            XCTAssertEqual(
                $0 as? SignalTeachByDemoRecordingSetupError,
                .secureTargetCannotBeReviewed
            )
        }
        XCTAssertTrue(authorizer.targets.isEmpty)
        XCTAssertFalse(model.message.contains(secretTitle))
        XCTAssertFalse(model.errorMessage?.contains(secretIdentifier) == true)
    }

    func testURLRequiresReviewedAppAndPublicHTTPS() throws {
        let authorizer = FakeSetupAuthorizer()
        let model = SignalTeachByDemoRecordingSetupModel(
            inspector: FakeSetupInspector(
                application: makeApplication(),
                target: nil
            ),
            authorizer: authorizer
        )
        model.inspectFrontmostContext()
        model.reviewedURLText = "https://example.com"
        XCTAssertThrowsError(try model.authorizeHTTPSURL()) {
            XCTAssertEqual(
                $0 as? SignalTeachByDemoRecordingSetupError,
                .reviewApplicationFirst
            )
        }
        try model.authorizeCandidateApplication()
        model.reviewedURLText = "http://example.com"
        XCTAssertThrowsError(try model.authorizeHTTPSURL())
        XCTAssertTrue(authorizer.urls.isEmpty)
    }

    func testConstructionHasNoInspectionAuthorizationOrCapture() {
        let inspector = FakeSetupInspector(
            application: makeApplication(),
            target: makeTarget()
        )
        let authorizer = FakeSetupAuthorizer()
        _ = SignalTeachByDemoRecordingSetupModel(
            inspector: inspector,
            authorizer: authorizer
        )
        XCTAssertEqual(inspector.inspections, 0)
        XCTAssertEqual(authorizer.authorizationCount, 0)
    }

    private func makeApplication() -> SignalTeachByDemoApplication {
        SignalTeachByDemoApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.Browser",
            localizedName: "Example Browser"
        )
    }

    private func makeTarget() -> SignalReviewedAccessibilityTarget {
        SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier: "com.example.Browser",
            role: "AXButton",
            title: "Continue",
            identifier: "continue-button",
            wasUserReviewed: false
        )
    }
}

@MainActor
private final class FakeSetupInspector:
    SignalTeachByDemoSetupInspecting
{
    let application: SignalTeachByDemoApplication?
    let target: SignalReviewedAccessibilityTarget?
    private(set) var inspections = 0

    init(
        application: SignalTeachByDemoApplication?,
        target: SignalReviewedAccessibilityTarget?
    ) {
        self.application = application
        self.target = target
    }

    func frontmostApplication() -> SignalTeachByDemoApplication? {
        inspections += 1
        return application
    }

    func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalReviewedAccessibilityTarget? {
        inspections += 1
        return target
    }
}

@MainActor
private final class FakeSetupAuthorizer:
    SignalTeachByDemoReviewAuthorizing
{
    private(set) var applications: [String] = []
    private(set) var targets:
        [SignalReviewedAccessibilityTarget] = []
    private(set) var urls: [String: String] = [:]

    var authorizationCount: Int {
        applications.count + targets.count + urls.count
    }

    func reviewApplication(bundleIdentifier: String) {
        applications.append(bundleIdentifier)
    }

    func reviewTarget(
        _ target: SignalReviewedAccessibilityTarget
    ) {
        targets.append(target)
    }

    func reviewHTTPSURL(
        _ rawURL: String,
        forApplication bundleIdentifier: String
    ) throws {
        urls[bundleIdentifier] = rawURL
    }

    func revokeAll() {
        applications = []
        targets = []
        urls = [:]
    }
}
