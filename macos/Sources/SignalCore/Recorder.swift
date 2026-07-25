import Foundation

public struct RecordedTimelineItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var offset: TimeInterval
    public var step: ActionStep
    public var masked: Bool

    public init(id: UUID = UUID(), offset: TimeInterval, step: ActionStep, masked: Bool = false) {
        self.id = id
        self.offset = offset
        self.step = step
        self.masked = masked
    }
}

public enum RecorderState: String, Codable, Equatable, Sendable {
    case idle
    case countdown
    case recording
    case reviewing
    case cancelled
}

public enum RecorderError: Error, Equatable {
    case notRecording
    case unsupportedAction
    case sensitiveTextRequiresConsent
}

/// Controlled Action Lab recorder. It captures semantic actions only and never global raw events.
public struct ControlledDemoRecorder: Sendable {
    public private(set) var state: RecorderState = .idle
    public private(set) var items: [RecordedTimelineItem] = []
    public private(set) var startedAt: TimeInterval?
    public var typedTextConsent = false
    public var minimumWaitToRecord = 0.35

    private var lastEventAt: TimeInterval?

    public init() {}

    public mutating func beginCountdown() {
        items = []
        startedAt = nil
        lastEventAt = nil
        state = .countdown
    }

    public mutating func start(at timestamp: TimeInterval) {
        items = []
        startedAt = timestamp
        lastEventAt = timestamp
        state = .recording
    }

    public mutating func record(_ step: ActionStep, at timestamp: TimeInterval) throws {
        guard state == .recording, let startedAt else { throw RecorderError.notRecording }
        let allowed: Set<ActionKind> = [
            .openApplication, .openURL, .keyboardShortcut, .typeText, .wait,
            .showNotification, .speakText, .discordWebhook, .slackWebhook
        ]
        guard allowed.contains(step.action) else { throw RecorderError.unsupportedAction }
        if step.action == .typeText && !typedTextConsent {
            throw RecorderError.sensitiveTextRequiresConsent
        }

        if let lastEventAt {
            let gap = timestamp - lastEventAt
            if gap >= minimumWaitToRecord, step.action != .wait {
                items.append(RecordedTimelineItem(
                    offset: lastEventAt - startedAt,
                    step: ActionStep(
                        action: .wait,
                        parameters: ["durationMs": .number((gap * 1_000).rounded())],
                        timeoutMs: Int(min(gap + 1, 60) * 1_000)
                    )
                ))
            }
        }
        items.append(RecordedTimelineItem(offset: timestamp - startedAt, step: step))
        lastEventAt = timestamp
    }

    public mutating func stop(name: String) throws -> ActionPlan {
        guard state == .recording else { throw RecorderError.notRecording }
        state = .reviewing
        return ActionPlan(
            name: name,
            description: "Recorded in Signal Action Lab",
            steps: items.filter { !$0.masked }.map(\.step),
            timeoutMs: Int(max(30, items.last.map { $0.offset + 10 } ?? 30) * 1_000),
            confirmation: Confirmation(mode: .firstRun, reason: "Review the recorded timeline."),
            createdSource: .demoRecording,
            approved: false
        )
    }

    public mutating func delete(itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    public mutating func move(from offsets: IndexSet, to destination: Int) {
        var moving: [RecordedTimelineItem] = []
        for index in offsets.sorted(by: >) where items.indices.contains(index) {
            moving.insert(items.remove(at: index), at: 0)
        }
        items.insert(contentsOf: moving, at: min(destination, items.count))
    }

    public mutating func cancel() {
        items = []
        state = .cancelled
        startedAt = nil
        lastEventAt = nil
    }
}

public struct RecorderEventCompressor: Sendable {
    public init() {}

    public func compress(_ events: [RecordedTimelineItem]) -> [RecordedTimelineItem] {
        var output: [RecordedTimelineItem] = []
        for event in events.sorted(by: { $0.offset < $1.offset }) {
            if event.step.action == .wait,
               let previous = output.last,
               previous.step.action == .wait {
                let combined = (previous.step.parameters["seconds"]?.numberValue ?? 0) +
                    (event.step.parameters["seconds"]?.numberValue ?? 0)
                output[output.count - 1].step.parameters["seconds"] = .number(combined)
            } else if event.step.action == .scrollAmount,
                      let previous = output.last,
                      previous.step.action == .scrollAmount,
                      event.offset - previous.offset < 0.15 {
                let horizontal = (previous.step.parameters["horizontal"]?.numberValue ?? 0) +
                    (event.step.parameters["horizontal"]?.numberValue ?? 0)
                let vertical = (previous.step.parameters["vertical"]?.numberValue ?? 0) +
                    (event.step.parameters["vertical"]?.numberValue ?? 0)
                output[output.count - 1].step.parameters["horizontal"] = .number(horizontal)
                output[output.count - 1].step.parameters["vertical"] = .number(vertical)
            } else {
                output.append(event)
            }
        }
        return output
    }
}
