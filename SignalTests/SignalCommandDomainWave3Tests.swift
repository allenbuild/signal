import Foundation
import XCTest
@testable import Signal

final class SignalCommandDomainWave3Tests: XCTestCase {
    func testCommandGestureSetIsExactlyEightAndRejectsFive() throws {
        XCTAssertEqual(
            SignalCommandGesture.allCases,
            [.one, .two, .three, .four, .thumbsUp, .thumbsDown, .cShape, .fist]
        )
        XCTAssertEqual(Set(SignalCommandGesture.allCases).count, 8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SignalCommandGesture.self,
                from: Data(#""five""#.utf8)
            )
        )
    }

    func testDefaultCatalogIsDeterministicExactAndValid() throws {
        let document = SignalDefaultCommandCatalog.document
        XCTAssertNoThrow(try SignalCommandValidator().validate(document))
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.catalogVersion, 1)
        XCTAssertEqual(document.profile.commands.count, 8)
        XCTAssertEqual(
            document.profile.commands.map(\.gesture),
            SignalCommandGesture.allCases
        )

        XCTAssertEqual(
            try openURL(for: .one, in: document),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            try openURL(for: .two, in: document),
            "https://mail.google.com/mail/?view=cm&fs=1&to=allenjxu07%40gmail.com"
        )
        XCTAssertEqual(
            try openURL(for: .three, in: document),
            "https://cursor.com/agents"
        )
        XCTAssertEqual(
            try openURL(for: .four, in: document),
            "https://doc.new"
        )
        XCTAssertEqual(
            try openURL(for: .cShape, in: document),
            "https://x.com/AnthropicAI?lang=en"
        )

        let gmailURL = try XCTUnwrap(URLComponents(string: try openURL(for: .two, in: document)))
        XCTAssertEqual(gmailURL.queryItems?.first(where: { $0.name == "to" })?.value, "allenjxu07@gmail.com")

        let bolt = try XCTUnwrap(document.profile[.thumbsUp]?.plan?.steps.first)
        guard case .boltPrompt(let payload) = bolt.action else {
            return XCTFail("Thumbs Up must use the closed Bolt action.")
        }
        XCTAssertEqual(payload.prompt, "i want to build a website for my hand signal app")

        let spotify = try XCTUnwrap(document.profile[.thumbsDown]?.plan?.steps.first)
        guard case .spotifyNextTrack = spotify.action else {
            return XCTFail("Thumbs Down must use the closed Spotify action.")
        }

        let fist = try XCTUnwrap(document.profile[.fist])
        XCTAssertTrue(fist.isConfigurable)
        XCTAssertNil(fist.plan)
        XCTAssertFalse(document.profile.commands.contains { $0.gesture.rawValue == "five" })
    }

    func testURLPolicyRejectsNonHTTPSCredentialsPortsAndPrivateDestinations() throws {
        let policy = SignalCommandURLPolicy()
        XCTAssertEqual(
            try policy.validate("https://doc.new").absoluteString,
            "https://doc.new"
        )
        let rejected = [
            "http://example.com",
            "https://user:pass@example.com",
            "https://example.com:8443",
            "https://localhost",
            "https://service.local",
            "https://127.0.0.1",
            "https://2130706433",
            "https://0x7f000001",
            "https://[::1]",
            "https://ｅxample.com",
            "https://%65xample.com",
            "https://example.com:",
            "https://example.com:0443",
            "file:///tmp/command",
            "javascript:alert(1)"
        ]
        for value in rejected {
            XCTAssertThrowsError(try policy.validate(value), "Accepted \(value)")
        }
        XCTAssertThrowsError(
            try policy.validate("https://example.com/path", exactHost: "bolt.new")
        )
    }

    func testSevenFixedCommandsCannotBeModifiedOrReordered() throws {
        let validator = SignalCommandValidator()
        let defaults = SignalDefaultCommandCatalog.document
        let oneIndex = try XCTUnwrap(
            defaults.profile.commands.firstIndex { $0.gesture == .one }
        )

        var changedID = defaults
        changedID.profile.commands[oneIndex].id = "signal.modified.one"

        var changedName = defaults
        changedName.profile.commands[oneIndex].name = "Different command"

        var changedPlan = defaults
        changedPlan.profile.commands[oneIndex].plan?.timeoutMilliseconds += 1

        var changedAction = defaults
        changedAction.profile.commands[oneIndex].plan?.steps[0].action =
            .openURL(.init(url: "https://example.com/not-the-default"))

        var reordered = defaults
        reordered.profile.commands.swapAt(0, 1)

        for document in [
            changedID,
            changedName,
            changedPlan,
            changedAction,
            reordered
        ] {
            XCTAssertThrowsError(try validator.validate(document))
        }
    }

    func testFistMayVaryButCannotSmuggleAnUnreviewedBoltPrompt() throws {
        let validator = SignalCommandValidator()
        var document = SignalDefaultCommandCatalog.document
        let fistIndex = try XCTUnwrap(
            document.profile.commands.firstIndex { $0.gesture == .fist }
        )
        document.profile.commands[fistIndex].id = "signal.custom.focus"
        document.profile.commands[fistIndex].name = "Focus"
        document.profile.commands[fistIndex].details = "Open a reviewed focus URL."
        document.profile.commands[fistIndex].plan = SignalCommandPlan(
            id: "signal.custom.focus.plan",
            steps: [
                SignalCommandStep(
                    id: "signal.custom.focus.open",
                    action: .openURL(.init(url: "https://example.com/focus"))
                )
            ]
        )
        XCTAssertNoThrow(try validator.validate(document))

        document.profile.commands[fistIndex].plan = SignalCommandPlan(
            id: "signal.custom.focus.plan",
            steps: [
                SignalCommandStep(
                    id: "signal.custom.focus.bolt",
                    action: .boltPrompt(.init(prompt: "an unreviewed prompt"))
                )
            ]
        )
        XCTAssertThrowsError(try validator.validate(document))
    }

    func testClosedJSONRejectsUnknownFieldsActionsAndFive() throws {
        let validator = SignalCommandValidator()
        let encoded = try JSONEncoder().encode(SignalDefaultCommandCatalog.document)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        root["unexpected"] = true
        let unknownFieldData = try JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try validator.validateClosedJSON(unknownFieldData)) { error in
            XCTAssertEqual(
                error as? SignalCommandValidationError,
                .unexpectedJSONField(path: "$", field: "unexpected")
            )
        }

        let unknownAction = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: #""open_url""#, with: #""shell_command""#)
        XCTAssertThrowsError(
            try validator.validateClosedJSON(Data(unknownAction.utf8))
        )

        let five = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: #""one""#, with: #""five""#, maxReplacements: 1)
        XCTAssertThrowsError(
            try JSONDecoder().decode(SignalCommandDocument.self, from: Data(five.utf8))
        )
    }

    @MainActor
    func testRepositoryRoundTripImportExportAndFistPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalCommandDomainWave3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = SignalCommandRepository(directory: root.appendingPathComponent("store"))
        var document = try await repository.loadOrInstallDefaults()
        let fistIndex = try XCTUnwrap(
            document.profile.commands.firstIndex { $0.gesture == .fist }
        )
        document.profile.commands[fistIndex].id = "signal.custom.fist"
        document.profile.commands[fistIndex].name = "Saved Focus Command"
        document.profile.commands[fistIndex].details =
            "A persisted, safe Fist command."
        document.profile.commands[fistIndex].plan = SignalCommandPlan(
            id: "signal.custom.fist.plan",
            steps: [
                SignalCommandStep(
                    id: "signal.custom.fist.step-1",
                    action: .openURL(.init(url: "https://example.com/signal"))
                )
            ]
        )
        try await repository.save(document)

        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded, document)
        XCTAssertNotNil(reloaded.profile[.fist]?.plan)
        XCTAssertEqual(reloaded.profile[.fist]?.name, "Saved Focus Command")

        let firstEncoding = try await repository.encodedData(for: reloaded)
        let secondEncoding = try await repository.encodedData(for: reloaded)
        XCTAssertEqual(firstEncoding, secondEncoding)

        let exportURL = root.appendingPathComponent("export/signal-commands.json")
        try await repository.export(reloaded, to: exportURL)
        let imported = try await repository.importDocument(from: exportURL)
        XCTAssertEqual(imported, reloaded)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstEncoding) as? [String: Any]
        )
        object["inlineSecret"] = "must-not-be-accepted"
        let unsafeImport = root.appendingPathComponent("unsafe.json")
        try JSONSerialization.data(withJSONObject: object).write(to: unsafeImport)
        do {
            _ = try await repository.importDocument(from: unsafeImport)
            XCTFail("Unknown import fields must be rejected.")
        } catch let error as SignalCommandValidationError {
            XCTAssertEqual(
                error,
                .unexpectedJSONField(path: "$", field: "inlineSecret")
            )
        }

        var modifiedFixedCommand = SignalDefaultCommandCatalog.document
        let oneIndex = try XCTUnwrap(
            modifiedFixedCommand.profile.commands.firstIndex {
                $0.gesture == .one
            }
        )
        modifiedFixedCommand.profile.commands[oneIndex].plan?.steps[0].action =
            .openURL(.init(url: "https://example.com/replaced-default"))
        let modifiedImport = root.appendingPathComponent("modified-fixed.json")
        try JSONEncoder().encode(modifiedFixedCommand).write(to: modifiedImport)
        do {
            _ = try await repository.importDocument(from: modifiedImport)
            XCTFail("Modified fixed commands must be rejected during import.")
        } catch {
            // Expected.
        }
    }

    func testActivationFiresOnceUntilReleaseAndHonorsCooldown() {
        var engine = SignalCommandActivationEngine(
            configuration: .init(
                holdDuration: 0.6,
                cooldownDuration: 0.9,
                confidenceThreshold: 0.7
            )
        )

        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0, gesture: .one, confidence: 0.9)),
            .progressing(gesture: .one, progress: 0)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0.3, gesture: .one, confidence: 0.9)),
            .progressing(gesture: .one, progress: 0.5)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0.6, gesture: .one, confidence: 0.9)),
            .triggered(.one)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 2.0, gesture: .one, confidence: 0.9)),
            .waitingForRelease(.one)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 2.1, gesture: nil, confidence: 0)),
            .idle
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 2.2, gesture: .one, confidence: 0.9)),
            .progressing(gesture: .one, progress: 0)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 2.8, gesture: .one, confidence: 0.9)),
            .triggered(.one)
        )
    }

    func testActivationSanitizesNonFiniteMutableConfiguration() {
        var engine = SignalCommandActivationEngine()
        engine.configuration.holdDuration = .nan
        engine.configuration.cooldownDuration = .infinity
        engine.configuration.confidenceThreshold = -.infinity

        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0, gesture: .one, confidence: 0.9)),
            .progressing(gesture: .one, progress: 0)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0.6, gesture: .one, confidence: 0.9)),
            .triggered(.one)
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 5, gesture: .one, confidence: 0.9)),
            .waitingForRelease(.one)
        )
    }

    func testActivationRejectsOutOfRangeConfidenceWithoutAccumulatingHold() {
        var engine = SignalCommandActivationEngine(
            configuration: .init(
                holdDuration: 0.6,
                cooldownDuration: 0.9,
                confidenceThreshold: 0.7
            )
        )

        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 0, gesture: .one, confidence: 1.01)),
            .idle
        )
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 1, gesture: .one, confidence: 0.9)),
            .progressing(gesture: .one, progress: 0)
        )
        let progress = engine.process(
            .init(monotonicSeconds: 1.59, gesture: .one, confidence: 0.9)
        )
        guard case .progressing(let gesture, let value) = progress else {
            return XCTFail("Expected a progressing activation.")
        }
        XCTAssertEqual(gesture, .one)
        XCTAssertEqual(value, 0.59 / 0.6, accuracy: 1e-12)
        XCTAssertEqual(
            engine.process(.init(monotonicSeconds: 1.6, gesture: .one, confidence: 0.9)),
            .triggered(.one)
        )
    }

    private func openURL(
        for gesture: SignalCommandGesture,
        in document: SignalCommandDocument
    ) throws -> String {
        let step = try XCTUnwrap(document.profile[gesture]?.plan?.steps.first)
        guard case .openURL(let payload) = step.action else {
            throw TestFailure.unexpectedAction
        }
        return payload.url
    }
}

private enum TestFailure: Error {
    case unexpectedAction
}

private extension String {
    func replacingOccurrences(
        of target: String,
        with replacement: String,
        maxReplacements: Int
    ) -> String {
        var result = self
        for _ in 0..<maxReplacements {
            guard let range = result.range(of: target) else { break }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
