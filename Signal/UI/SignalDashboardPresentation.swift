import Foundation

public enum SignalDashboardMode: String, CaseIterable, Identifiable, Sendable {
    case paused
    case control
    case commands

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paused: "Paused"
        case .control: "Control"
        case .commands: "Commands"
        }
    }
}

public enum SignalDashboardCardID: String, CaseIterable, Identifiable, Sendable {
    case one
    case two
    case three
    case four
    case thumbsUp
    case thumbsDown
    case cShape
    case fist

    public var id: String { rawValue }
}

public struct SignalDashboardCommandCard: Identifiable, Equatable, Sendable {
    public var id: SignalDashboardCardID
    public var gestureLabel: String
    public var commandName: String
    public var symbolName: String
    public var isConfigured: Bool
    public var isEnabled: Bool

    public init(
        id: SignalDashboardCardID,
        gestureLabel: String,
        commandName: String,
        symbolName: String,
        isConfigured: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.gestureLabel = gestureLabel
        self.commandName = commandName
        self.symbolName = symbolName
        self.isConfigured = isConfigured
        self.isEnabled = isEnabled
    }

    public static let canonical: [Self] = [
        .init(
            id: .one,
            gestureLabel: "One",
            commandName: "Rickroll",
            symbolName: "1.circle.fill"
        ),
        .init(
            id: .two,
            gestureLabel: "Two",
            commandName: "New Gmail",
            symbolName: "2.circle.fill"
        ),
        .init(
            id: .three,
            gestureLabel: "Three",
            commandName: "Cursor Agents",
            symbolName: "3.circle.fill"
        ),
        .init(
            id: .four,
            gestureLabel: "Four",
            commandName: "New Google Doc",
            symbolName: "4.circle.fill"
        ),
        .init(
            id: .thumbsUp,
            gestureLabel: "Thumbs Up",
            commandName: "Build with Bolt",
            symbolName: "hand.thumbsup.fill"
        ),
        .init(
            id: .thumbsDown,
            gestureLabel: "Thumbs Down",
            commandName: "Next Spotify Track",
            symbolName: "hand.thumbsdown.fill"
        ),
        .init(
            id: .cShape,
            gestureLabel: "C",
            commandName: "Anthropic on X",
            symbolName: "c.circle.fill"
        ),
        .init(
            id: .fist,
            gestureLabel: "Fist",
            commandName: "Custom Command",
            symbolName: "hand.raised.fill"
        ),
    ]
}

public enum SignalDashboardStatusKind: String, Sendable {
    case paused
    case ready
    case attention
    case error
}

public struct SignalDashboardStatus: Equatable, Sendable {
    public var kind: SignalDashboardStatusKind
    public var title: String
    public var detail: String

    public init(
        kind: SignalDashboardStatusKind,
        title: String,
        detail: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public static let paused = Self(
        kind: .paused,
        title: "Signal is paused",
        detail: "Choose Control or Commands to enable output explicitly."
    )
}

public enum SignalDashboardPermissionKind:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case camera
    case accessibility
    case browserAutomation
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .accessibility: "Accessibility"
        case .browserAutomation: "Browser Automation"
        case .screenRecording: "Screen Recording"
        }
    }

    public var isCorePermission: Bool {
        self == .camera || self == .accessibility
    }
}

public enum SignalDashboardPermissionState: String, Sendable {
    case granted
    case notDetermined
    case denied
    case restricted
    case requiresRelaunch
    case optional
    case notRequired

    public var title: String {
        switch self {
        case .granted: "Granted"
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .requiresRelaunch: "Requires relaunch"
        case .optional: "Optional"
        case .notRequired: "Not required"
        }
    }

    public var needsUserAction: Bool {
        switch self {
        case .notDetermined, .denied, .restricted, .requiresRelaunch:
            true
        case .granted, .optional, .notRequired:
            false
        }
    }
}

public struct SignalDashboardPermission: Identifiable, Equatable, Sendable {
    public var id: SignalDashboardPermissionKind { kind }
    public var kind: SignalDashboardPermissionKind
    public var state: SignalDashboardPermissionState
    public var detail: String

    public init(
        kind: SignalDashboardPermissionKind,
        state: SignalDashboardPermissionState,
        detail: String = ""
    ) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }
}

public struct SignalDashboardTelemetry: Equatable, Sendable {
    public var cameraState: String
    public var trackingQuality: String
    public var recognizedPose: String
    public var confidence: Double
    public var captureFPS: Double
    public var processedFPS: Double
    public var visionLatencyMilliseconds: Double
    public var endToEndLatencyMilliseconds: Double
    public var controlTransaction: String
    public var activeApplication: String
    public var activeZoomProfile: String

    public init(
        cameraState: String = "Stopped",
        trackingQuality: String = "Absent",
        recognizedPose: String = "None",
        confidence: Double = 0,
        captureFPS: Double = 0,
        processedFPS: Double = 0,
        visionLatencyMilliseconds: Double = 0,
        endToEndLatencyMilliseconds: Double = 0,
        controlTransaction: String = "Idle",
        activeApplication: String = "None",
        activeZoomProfile: String = "None"
    ) {
        self.cameraState = cameraState
        self.trackingQuality = trackingQuality
        self.recognizedPose = recognizedPose
        self.confidence = Self.unitInterval(confidence)
        self.captureFPS = Self.nonnegative(captureFPS)
        self.processedFPS = Self.nonnegative(processedFPS)
        self.visionLatencyMilliseconds = Self.nonnegative(visionLatencyMilliseconds)
        self.endToEndLatencyMilliseconds = Self.nonnegative(
            endToEndLatencyMilliseconds
        )
        self.controlTransaction = controlTransaction
        self.activeApplication = activeApplication
        self.activeZoomProfile = activeZoomProfile
    }

    private static func nonnegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private static func unitInterval(_ value: Double) -> Double {
        min(max(nonnegative(value), 0), 1)
    }
}

public enum SignalDashboardActivityOutcome: String, Sendable {
    case information
    case success
    case failure
}

public struct SignalDashboardActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var title: String
    public var detail: String
    public var outcome: SignalDashboardActivityOutcome

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        title: String,
        detail: String = "",
        outcome: SignalDashboardActivityOutcome = .information
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.outcome = outcome
    }
}

public struct SignalDashboardPresentation: Equatable, Sendable {
    public static let maximumActivityItems = 100

    public var mode: SignalDashboardMode
    public var status: SignalDashboardStatus
    public private(set) var cards: [SignalDashboardCommandCard]
    public var permissions: [SignalDashboardPermission]
    public var telemetry: SignalDashboardTelemetry
    public var activeCardID: SignalDashboardCardID?
    public private(set) var activationProgress: Double
    public var lastCommand: String
    public var lastCommandResult: String
    public private(set) var activity: [SignalDashboardActivity]

    public init(
        mode: SignalDashboardMode = .paused,
        status: SignalDashboardStatus = .paused,
        cards: [SignalDashboardCommandCard] =
            SignalDashboardCommandCard.canonical,
        permissions: [SignalDashboardPermission] = [],
        telemetry: SignalDashboardTelemetry = .init(),
        activeCardID: SignalDashboardCardID? = nil,
        activationProgress: Double = 0,
        lastCommand: String = "None",
        lastCommandResult: String = "No command has run.",
        activity: [SignalDashboardActivity] = []
    ) {
        self.mode = mode
        self.status = status
        self.cards = Self.canonicalized(cards)
        self.permissions = permissions
        self.telemetry = telemetry
        self.activeCardID = activeCardID
        self.activationProgress = Self.unitInterval(activationProgress)
        self.lastCommand = lastCommand
        self.lastCommandResult = lastCommandResult
        self.activity = Array(activity.prefix(Self.maximumActivityItems))
    }

    public mutating func setActivation(
        cardID: SignalDashboardCardID?,
        progress: Double
    ) {
        activeCardID = cardID
        activationProgress = Self.unitInterval(progress)
    }

    public mutating func recordActivity(_ entry: SignalDashboardActivity) {
        activity.insert(entry, at: 0)
        if activity.count > Self.maximumActivityItems {
            activity.removeLast(activity.count - Self.maximumActivityItems)
        }
    }

    /// The seven reviewed defaults remain fixed. Only the Fist card reflects
    /// repository-authored content.
    public mutating func updateFistCommand(
        name: String,
        isConfigured: Bool
    ) {
        guard let index = cards.firstIndex(where: { $0.id == .fist }) else {
            return
        }
        cards[index].commandName = name
        cards[index].isConfigured = isConfigured
        cards[index].isEnabled = true
    }

    private static func canonicalized(
        _ supplied: [SignalDashboardCommandCard]
    ) -> [SignalDashboardCommandCard] {
        let suppliedByID = supplied.reduce(
            into: [SignalDashboardCardID: SignalDashboardCommandCard]()
        ) { result, card in
            if result[card.id] == nil {
                result[card.id] = card
            }
        }
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: SignalDashboardCommandCard.canonical.map {
                ($0.id, $0)
            }
        )
        return SignalDashboardCardID.allCases.compactMap {
            suppliedByID[$0] ?? defaultsByID[$0]
        }
    }

    private static func unitInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct SignalDashboardActions: Sendable {
    public var selectMode: @MainActor @Sendable (SignalDashboardMode) -> Void
    public var editCommand:
        @MainActor @Sendable (SignalDashboardCardID) -> Void
    public var requestPermission:
        @MainActor @Sendable (SignalDashboardPermissionKind) -> Void
    public var openCalibration: @MainActor @Sendable () -> Void
    public var openSettings: @MainActor @Sendable () -> Void
    public var emergencyStop: @MainActor @Sendable () -> Void

    public init(
        selectMode: @escaping @MainActor @Sendable (SignalDashboardMode) -> Void,
        editCommand:
            @escaping @MainActor @Sendable (SignalDashboardCardID) -> Void,
        requestPermission:
            @escaping @MainActor @Sendable (SignalDashboardPermissionKind) -> Void,
        openCalibration: @escaping @MainActor @Sendable () -> Void,
        openSettings: @escaping @MainActor @Sendable () -> Void,
        emergencyStop: @escaping @MainActor @Sendable () -> Void
    ) {
        self.selectMode = selectMode
        self.editCommand = editCommand
        self.requestPermission = requestPermission
        self.openCalibration = openCalibration
        self.openSettings = openSettings
        self.emergencyStop = emergencyStop
    }

    public static let inert = Self(
        selectMode: { _ in },
        editCommand: { _ in },
        requestPermission: { _ in },
        openCalibration: {},
        openSettings: {},
        emergencyStop: {}
    )
}
