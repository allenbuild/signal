import Foundation
import XCTest
@testable import SignalCore

final class SchemaProfilePlannerTests: XCTestCase {
    func testExactFrozenSharedSeedAndPlannerFilesDecode() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let macosRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let worktreeRoot = macosRoot.deletingLastPathComponent()
        let candidates = [
            worktreeRoot.appendingPathComponent("shared"),
            worktreeRoot.deletingLastPathComponent()
                .appendingPathComponent("contracts-docs/shared")
        ]
        guard let shared = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("seeded-demo-profile.json").path)
        }) else {
            return XCTFail("Frozen shared fixtures were not found")
        }
        let profileData = try Data(contentsOf: shared.appendingPathComponent("seeded-demo-profile.json"))
        let profile = try JSONDecoder().decode(SignalProfile.self, from: profileData)
        XCTAssertNoThrow(try ProfileValidator().validate(profile))
        XCTAssertEqual(Set(profile.mappings.map(\.gesture)), Set([.one, .thumbsUp, .cShape]))

        let plannerData = try Data(contentsOf: shared.appendingPathComponent("examples/planner-response.json"))
        let planner = try JSONDecoder().decode(PlannerResponse.self, from: plannerData)
        XCTAssertNoThrow(try planner.validate())
    }

    func testFrozenV1PlannerExampleDecodesAndValidates() throws {
        let response = try JSONDecoder().decode(PlannerResponse.self, from: Data(Self.plannerJSON.utf8))
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.status, .planned)
        XCTAssertEqual(response.plan?.steps.map(\.action), [.openURL, .speakText, .discordWebhook])
        XCTAssertNoThrow(try response.validate())
    }

    func testFrozenV1ProfileExampleDecodesAndValidates() throws {
        let profile = try JSONDecoder().decode(SignalProfile.self, from: Data(Self.profileJSON.utf8))
        XCTAssertEqual(profile.preferredMode, .hybrid)
        XCTAssertEqual(profile.mappings.first?.gesture, .cShape)
        XCTAssertEqual(profile.mappings.first?.plan.steps.first?.action, .openApplication)
        XCTAssertNoThrow(try ProfileValidator().validate(profile))
    }

    func testCanonicalSeedInstallsOneThumbsUpAndCShape() throws {
        let profile = SeededContent.demoProfile()
        XCTAssertEqual(Set(profile.mappings.map(\.gesture)), Set([.one, .thumbsUp, .cShape]))
        XCTAssertNoThrow(try ProfileValidator().validate(profile))
        XCTAssertEqual(
            profile.mappings.first(where: { $0.gesture == .one })?
                .plan.steps.first?.parameters["networkPolicy"]?.stringValue,
            "public_https_only"
        )
    }

    func testUnsupportedFutureVersionsAreRejected() throws {
        var plan = SeededContent.focusPlan(approved: true)
        plan.schemaVersion = 2
        XCTAssertThrowsError(try ActionPlanValidator().validate(plan)) {
            XCTAssertEqual($0 as? ModelValidationError, .unsupportedSchemaVersion(2))
        }
        var profile = SeededContent.demoProfile()
        profile.schemaVersion = 9
        XCTAssertThrowsError(try ProfileValidator().validate(profile))
    }

    func testPortableEncodingOmitsLocalApprovalAndRejectsRawSecrets() throws {
        let encoded = try JSONEncoder().encode(SeededContent.focusPlan(approved: true))
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("\"approved\""))
        XCTAssertFalse(text.contains("token"))

        var plan = SeededContent.focusPlan(approved: true)
        plan.steps[0].parameters["password"] = .string("do-not-serialize")
        XCTAssertThrowsError(try ActionPlanValidator().validate(plan))
    }

    func testURLPolicyRejectsLocalhostPrivateAndPlainHTTP() {
        let validator = ActionPlanValidator(requireApproval: false)
        for value in [
            "http://example.com",
            "https://localhost/test",
            "https://127.0.0.1/test",
            "https://10.0.0.2/test",
            "https://172.31.5.4/test",
            "https://192.168.1.10/test",
            "https://169.254.1.2/test",
            "https://198.51.100.9/test",
            "https://user:password@example.com/test",
            "https://example.com:8443/test"
        ] {
            XCTAssertThrowsError(try validator.validatePublicURL(value), value)
        }
        XCTAssertNoThrow(try validator.validatePublicURL("https://example.com/path"))
    }

    func testPlannerDefaultsToPublicHTTPSAndSeededFallback() async throws {
        let configuration = PlannerConfiguration()
        XCTAssertEqual(configuration.endpoint.scheme, "https")
        XCTAssertEqual(configuration.endpoint.host, "signal-hand-control.allenxtech.chatgpt.site")
        let client = PlannerClient()
        let result = client.offlinePlan(for: "When I give a thumbs up, start focus mode")
        XCTAssertEqual(result.interpretedGesture, .thumbsUp)
        XCTAssertEqual(result.response.status, .planned)
        XCTAssertEqual(result.response.usedDeterministicFallback, true)
        XCTAssertNoThrow(try result.response.validate())
        let request = PlannerRequest(request: "Open an app")
        XCTAssertEqual(Set(request.actionCatalog), Set(NativeActionCatalog.executable))
        XCTAssertFalse(request.actionCatalog.contains(.httpRequest))
        XCTAssertFalse(request.actionCatalog.contains(.openDeepLink))
    }

    func testLocalProfileRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalProfileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalProfileStore(directory: directory)
        let profile = SeededContent.demoProfile()
        try await store.save(profile)
        let loaded = try await store.load(id: profile.id)
        XCTAssertEqual(loaded.id, profile.id)
        XCTAssertEqual(loaded.mappings.first?.plan.id, profile.mappings.first?.plan.id)
        XCTAssertFalse(loaded.mappings.first?.plan.approved ?? true, "Portable files never persist approval")
        let profiles = try await store.list()
        XCTAssertEqual(profiles.count, 1)
    }

    private static let plannerJSON = """
    {
      "schemaVersion": 1,
      "requestId": "demo-request-1",
      "status": "planned",
      "plan": {
        "schemaVersion": 1,
        "id": "signal.example.focus-mode",
        "name": "Focus mode",
        "description": "A validated example.",
        "steps": [
          {
            "id": "open-playlist",
            "action": {"type": "open_url", "parameters": {"url": "https://open.spotify.com/focus", "networkPolicy": "public_https_only"}},
            "timeoutMs": 10000,
            "onFailure": "continue",
            "confirmation": {"mode": "first_run", "reason": "Opens a public URL."}
          },
          {
            "id": "speak-cue",
            "action": {"type": "speak_text", "parameters": {"text": "Focus mode"}},
            "timeoutMs": 10000,
            "onFailure": "continue",
            "confirmation": {"mode": "none", "reason": "Local speech."}
          },
          {
            "id": "send-receipt",
            "action": {"type": "discord_webhook", "parameters": {"secretRef": "demo-discord", "message": "Demo complete", "fallback": "local_receipt"}},
            "timeoutMs": 10000,
            "onFailure": "continue",
            "confirmation": {"mode": "every_run", "reason": "External effect."}
          }
        ],
        "timeoutMs": 35000,
        "onFailure": "continue",
        "confirmation": {"mode": "first_run", "reason": "Review first."},
        "createdSource": "natural_language",
        "secretReferences": [{"id": "demo-discord", "provider": "discord", "purpose": "Receipt", "storage": "keychain_or_server_environment"}]
      },
      "warnings": [],
      "usedDeterministicFallback": false
    }
    """

    private static let profileJSON = """
    {
      "schemaVersion": 1,
      "id": "signal.seed.demo",
      "name": "Signal Demo",
      "description": "Test fixture",
      "preferredMode": "hybrid",
      "hybridOneBehavior": "pointer",
      "mappings": [{
        "gesture": "c_shape",
        "enabled": true,
        "holdDurationMs": 650,
        "cooldownMs": 1000,
        "activation": "one_shot",
        "allowedBundleIdentifiers": [],
        "preferredMode": "commands",
        "plan": {
          "schemaVersion": 1,
          "id": "signal.seed.replay",
          "name": "Replay",
          "description": "Open TextEdit",
          "steps": [{
            "id": "open-textedit",
            "action": {"type": "open_application", "parameters": {"bundleIdentifier": "com.apple.TextEdit", "applicationName": "TextEdit"}},
            "timeoutMs": 10000,
            "onFailure": "stop",
            "confirmation": {"mode": "first_run", "reason": "Opens an app."}
          }],
          "timeoutMs": 15000,
          "onFailure": "stop",
          "confirmation": {"mode": "first_run", "reason": "Review."},
          "createdSource": "demo_recording",
          "secretReferences": []
        }
      }],
      "share": {"visibility": "private"}
    }
    """
}
