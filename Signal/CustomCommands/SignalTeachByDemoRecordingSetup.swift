@preconcurrency import AppKit
import Foundation
import SwiftUI

@MainActor
public protocol SignalTeachByDemoSetupInspecting: AnyObject {
    func frontmostApplication() -> SignalTeachByDemoApplication?
    func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalReviewedAccessibilityTarget?
}

@MainActor
public protocol SignalTeachByDemoReviewAuthorizing: AnyObject {
    func reviewApplication(bundleIdentifier: String)
    func reviewTarget(_ target: SignalReviewedAccessibilityTarget)
    func reviewHTTPSURL(
        _ rawURL: String,
        forApplication bundleIdentifier: String
    ) throws
    func revokeAll()
}

extension SignalTeachByDemoReviewContext:
    SignalTeachByDemoReviewAuthorizing
{}

/// Read-only system inspection used by an explicit setup button. Inspection
/// does not mutate the review context or authorize capture.
@MainActor
public final class SignalTeachByDemoSystemSetupInspector:
    SignalTeachByDemoSetupInspecting
{
    private let resolver: SignalTeachByDemoAXContextResolver

    public init(resolver: SignalTeachByDemoAXContextResolver) {
        self.resolver = resolver
    }

    public func frontmostApplication()
        -> SignalTeachByDemoApplication?
    {
        guard let running = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = running.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }
        return SignalTeachByDemoApplication(
            processIdentifier: running.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: running.localizedName ?? bundleIdentifier
        )
    }

    public func focusedTarget(
        in application: SignalTeachByDemoApplication
    ) -> SignalReviewedAccessibilityTarget? {
        resolver.inspectFocusedTarget(in: application)
    }
}

public enum SignalTeachByDemoRecordingSetupError:
    Error,
    Equatable,
    LocalizedError
{
    case noFrontmostApplication
    case reviewApplicationFirst
    case noFocusedTarget
    case secureTargetCannotBeReviewed
    case invalidApplication
    case urlRequired

    public var errorDescription: String? {
        switch self {
        case .noFrontmostApplication:
            "No frontmost application could be inspected."
        case .reviewApplicationFirst:
            "Review the application before reviewing its target or URL."
        case .noFocusedTarget:
            "No focused accessibility target could be inspected."
        case .secureTargetCannotBeReviewed:
            "Secure fields cannot be reviewed or captured."
        case .invalidApplication:
            "The inspected application identifier is not safe."
        case .urlRequired:
            "Enter a public HTTPS URL to review."
        }
    }
}

@MainActor
public final class SignalTeachByDemoRecordingSetupModel:
    ObservableObject
{
    @Published public private(set) var candidateApplication:
        SignalTeachByDemoApplication?
    @Published public private(set) var candidateTarget:
        SignalReviewedAccessibilityTarget?
    @Published public private(set) var reviewedApplication:
        SignalTeachByDemoApplication?
    @Published public private(set) var reviewedTarget:
        SignalReviewedAccessibilityTarget?
    @Published public var reviewedURLText = ""
    @Published public private(set) var reviewedHTTPSURL: String?
    @Published public private(set) var message:
        String = "Inspect, then explicitly review what capture may observe."
    @Published public private(set) var errorMessage: String?

    private let inspector: any SignalTeachByDemoSetupInspecting
    private let authorizer: any SignalTeachByDemoReviewAuthorizing
    private let urlPolicy: SignalCommandURLPolicy

    public init(
        inspector: any SignalTeachByDemoSetupInspecting,
        authorizer: any SignalTeachByDemoReviewAuthorizing,
        urlPolicy: SignalCommandURLPolicy = .init()
    ) {
        self.inspector = inspector
        self.authorizer = authorizer
        self.urlPolicy = urlPolicy
    }

    /// Capture may start only after the application and at least one concrete
    /// capture boundary (a non-secure target or public HTTPS URL) were
    /// explicitly reviewed.
    public var isReadyToStart: Bool {
        reviewedApplication != nil
            && (reviewedTarget != nil || reviewedHTTPSURL != nil)
    }

    public func inspectFrontmostContext() {
        errorMessage = nil
        reviewedURLText = ""
        guard let application = inspector.frontmostApplication() else {
            candidateApplication = nil
            candidateTarget = nil
            fail(.noFrontmostApplication)
            return
        }
        candidateApplication = application
        candidateTarget = sanitized(
            inspector.focusedTarget(in: application)
        )
        message =
            "Inspection complete. Nothing was authorized; review each item explicitly."
    }

    public func authorizeCandidateApplication() throws {
        guard let application = candidateApplication else {
            throw fail(.noFrontmostApplication)
        }
        guard Self.isSafeBundleIdentifier(
            application.bundleIdentifier
        ) else {
            throw fail(.invalidApplication)
        }
        // A new app review defines a fresh, narrow capture boundary instead
        // of silently accumulating grants from an earlier setup.
        authorizer.revokeAll()
        authorizer.reviewApplication(
            bundleIdentifier: application.bundleIdentifier
        )
        reviewedApplication = application
        reviewedTarget = nil
        reviewedHTTPSURL = nil
        errorMessage = nil
        message = "Application reviewed for this capture session."
    }

    public func authorizeCandidateTarget() throws {
        guard let application = candidateApplication,
              reviewedApplication?.bundleIdentifier
                == application.bundleIdentifier else {
            throw fail(.reviewApplicationFirst)
        }
        guard let target = candidateTarget else {
            throw fail(.noFocusedTarget)
        }
        guard !target.isSecureField else {
            throw fail(.secureTargetCannotBeReviewed)
        }
        var reviewed = target
        reviewed.wasUserReviewed = true
        authorizer.reviewTarget(reviewed)
        reviewedTarget = reviewed
        errorMessage = nil
        message = "Focused non-secure target reviewed."
    }

    public func authorizeHTTPSURL() throws {
        guard let application = candidateApplication,
              reviewedApplication?.bundleIdentifier
                == application.bundleIdentifier else {
            throw fail(.reviewApplicationFirst)
        }
        guard !reviewedURLText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw fail(.urlRequired)
        }
        do {
            let url = try urlPolicy.validate(reviewedURLText)
            try authorizer.reviewHTTPSURL(
                url.absoluteString,
                forApplication: application.bundleIdentifier
            )
            reviewedHTTPSURL = url.absoluteString
            reviewedURLText = url.absoluteString
            errorMessage = nil
            message = "Public HTTPS URL reviewed."
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func clearAuthorization() {
        authorizer.revokeAll()
        reviewedApplication = nil
        reviewedTarget = nil
        reviewedHTTPSURL = nil
        reviewedURLText = ""
        errorMessage = nil
        message = "Capture authorization cleared."
    }

    @discardableResult
    private func fail(
        _ error: SignalTeachByDemoRecordingSetupError
    ) -> SignalTeachByDemoRecordingSetupError {
        errorMessage = error.localizedDescription
        return error
    }

    private func sanitized(
        _ target: SignalReviewedAccessibilityTarget?
    ) -> SignalReviewedAccessibilityTarget? {
        guard let target else { return nil }
        guard target.isSecureField else {
            var unreviewed = target
            unreviewed.wasUserReviewed = false
            return unreviewed
        }
        return SignalReviewedAccessibilityTarget(
            applicationBundleIdentifier:
                target.applicationBundleIdentifier,
            role: "AXSecureTextField",
            title: "Secure field",
            identifier: nil,
            isSecureField: true,
            wasUserReviewed: false
        )
    }

    private static func isSafeBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 255
            && value.contains(".")
            && value.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn:
                        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
                ).contains($0)
            }
    }
}

@MainActor
public struct SignalTeachByDemoRecordingSetupPanel: View {
    @ObservedObject private var model:
        SignalTeachByDemoRecordingSetupModel

    public init(model: SignalTeachByDemoRecordingSetupModel) {
        self.model = model
    }

    public var body: some View {
        GroupBox("Pre-capture review") {
            VStack(alignment: .leading, spacing: 9) {
                Text(
                    "Inspection never authorizes capture. Review only the context you intend to demonstrate."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Inspect frontmost context") {
                    model.inspectFrontmostContext()
                }

                if let application = model.candidateApplication {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(application.localizedName)
                            Text(application.bundleIdentifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Review App") {
                            try? model.authorizeCandidateApplication()
                        }
                    }
                }

                if let target = model.candidateTarget {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(target.title)
                            Text(target.role)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if target.isSecureField {
                            Label("Never captured", systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Button("Review Focused Target") {
                                try? model.authorizeCandidateTarget()
                            }
                            .disabled(model.reviewedApplication == nil)
                        }
                    }
                }

                HStack {
                    TextField(
                        "https://public.example/path",
                        text: $model.reviewedURLText
                    )
                    Button("Review HTTPS URL") {
                        try? model.authorizeHTTPSURL()
                    }
                    .disabled(model.reviewedApplication == nil)
                }

                HStack {
                    Label(
                        model.isReadyToStart
                            ? "Capture context reviewed"
                            : "Start locked until app and target or URL review",
                        systemImage: model.isReadyToStart
                            ? "checkmark.shield.fill"
                            : "lock.fill"
                    )
                    .foregroundStyle(
                        model.isReadyToStart ? .green : .secondary
                    )
                    Spacer()
                    Button("Clear authorization", role: .destructive) {
                        model.clearAuthorization()
                    }
                    .disabled(
                        model.reviewedApplication == nil
                            && model.reviewedTarget == nil
                            && model.reviewedHTTPSURL == nil
                    )
                }

                Text(model.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
