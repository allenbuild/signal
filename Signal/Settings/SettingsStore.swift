import Combine
import Foundation

public enum ZoomShortcutKeyCatalog {
    public struct Mapping: Equatable, Sendable {
        public var keyCode: UInt16
        public var requiresShift: Bool
    }

    /// Hardware-independent US ANSI virtual-key positions used by CGEvent.
    private static let mappings: [Character: Mapping] = [
        "a": .init(keyCode: 0, requiresShift: false), "s": .init(keyCode: 1, requiresShift: false),
        "d": .init(keyCode: 2, requiresShift: false), "f": .init(keyCode: 3, requiresShift: false),
        "h": .init(keyCode: 4, requiresShift: false), "g": .init(keyCode: 5, requiresShift: false),
        "z": .init(keyCode: 6, requiresShift: false), "x": .init(keyCode: 7, requiresShift: false),
        "c": .init(keyCode: 8, requiresShift: false), "v": .init(keyCode: 9, requiresShift: false),
        "b": .init(keyCode: 11, requiresShift: false), "q": .init(keyCode: 12, requiresShift: false),
        "w": .init(keyCode: 13, requiresShift: false), "e": .init(keyCode: 14, requiresShift: false),
        "r": .init(keyCode: 15, requiresShift: false), "y": .init(keyCode: 16, requiresShift: false),
        "t": .init(keyCode: 17, requiresShift: false), "1": .init(keyCode: 18, requiresShift: false),
        "2": .init(keyCode: 19, requiresShift: false), "3": .init(keyCode: 20, requiresShift: false),
        "4": .init(keyCode: 21, requiresShift: false), "6": .init(keyCode: 22, requiresShift: false),
        "5": .init(keyCode: 23, requiresShift: false), "=": .init(keyCode: 24, requiresShift: false),
        "+": .init(keyCode: 24, requiresShift: true), "9": .init(keyCode: 25, requiresShift: false),
        "7": .init(keyCode: 26, requiresShift: false), "-": .init(keyCode: 27, requiresShift: false),
        "_": .init(keyCode: 27, requiresShift: true), "8": .init(keyCode: 28, requiresShift: false),
        "0": .init(keyCode: 29, requiresShift: false), "]": .init(keyCode: 30, requiresShift: false),
        "o": .init(keyCode: 31, requiresShift: false), "u": .init(keyCode: 32, requiresShift: false),
        "[": .init(keyCode: 33, requiresShift: false), "i": .init(keyCode: 34, requiresShift: false),
        "p": .init(keyCode: 35, requiresShift: false), "l": .init(keyCode: 37, requiresShift: false),
        "j": .init(keyCode: 38, requiresShift: false), "'": .init(keyCode: 39, requiresShift: false),
        "k": .init(keyCode: 40, requiresShift: false), ";": .init(keyCode: 41, requiresShift: false),
        "\\": .init(keyCode: 42, requiresShift: false), ",": .init(keyCode: 43, requiresShift: false),
        "/": .init(keyCode: 44, requiresShift: false), "n": .init(keyCode: 45, requiresShift: false),
        "m": .init(keyCode: 46, requiresShift: false), ".": .init(keyCode: 47, requiresShift: false),
        "`": .init(keyCode: 50, requiresShift: false)
    ]

    public static func mapping(for value: String) -> Mapping? {
        guard let character = value.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return nil
        }
        return mappings[Character(String(character).lowercased())]
    }
}

public struct ZoomShortcutSetting: Codable, Equatable, Sendable {
    public var keyEquivalent: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(
        keyEquivalent: String,
        command: Bool = true,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) {
        self.keyEquivalent = keyEquivalent
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    public static let zoomInDefault = Self(keyEquivalent: "=", command: true, option: true)
    public static let zoomOutDefault = Self(keyEquivalent: "-", command: true, option: true)
    public static let resetDefault = Self(keyEquivalent: "0", command: true)

    public var displayText: String {
        let modifiers = [
            control ? "⌃" : "",
            option ? "⌥" : "",
            shift ? "⇧" : "",
            command ? "⌘" : ""
        ].joined()
        return modifiers + keyEquivalent
    }

    fileprivate var normalized: Self {
        var result = self
        let trimmed = keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines)
        result.keyEquivalent = String(trimmed.prefix(1))
        return result
    }

    fileprivate var isValid: Bool {
        ZoomShortcutKeyCatalog.mapping(for: normalized.keyEquivalent) != nil
    }
}

public struct ZoomApplicationProfileSetting: Codable, Equatable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    public var zoomIn: ZoomShortcutSetting
    public var zoomOut: ZoomShortcutSetting
    public var reset: ZoomShortcutSetting?

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        displayName: String,
        zoomIn: ZoomShortcutSetting = .zoomInDefault,
        zoomOut: ZoomShortcutSetting = .zoomOutDefault,
        reset: ZoomShortcutSetting? = .resetDefault
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
        self.reset = reset
    }

    fileprivate var normalized: Self {
        var result = self
        result.bundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.zoomIn = zoomIn.normalized
        result.zoomOut = zoomOut.normalized
        result.reset = reset?.normalized
        return result
    }

    fileprivate var isValid: Bool {
        let value = normalized
        return !value.bundleIdentifier.isEmpty
            && value.bundleIdentifier.contains(".")
            && !value.displayName.isEmpty
            && value.zoomIn.isValid
            && value.zoomOut.isValid
            && (value.reset?.isValid ?? true)
    }
}

private struct PersistedSignalSettings: Codable, Equatable {
    var tuning: GestureTuning
    var zoomProfiles: [ZoomApplicationProfileSetting]
    var screenZoomShortcutsEnabled: Bool?
}

@MainActor
public final class SettingsStore: ObservableObject {
    public static let storageKey = "Signal.settings.v1"

    @Published public private(set) var tuning: GestureTuning
    @Published public private(set) var zoomProfiles: [ZoomApplicationProfileSetting]
    @Published public private(set) var screenZoomShortcutsEnabled: Bool
    @Published public private(set) var lastValidationMessage: String?
    @Published public private(set) var configurationRevision: UInt64

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var persistenceNeedsSynchronization: Bool

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        configurationRevision = 0

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? decoder.decode(PersistedSignalSettings.self, from: data) {
            var migratedTuning = decoded.tuning
            let migratedMiddleThumbDefaults = !migratedTuning.hasStoredScrollStabilizationFrames
            if migratedMiddleThumbDefaults {
                migratedTuning.applyMiddleThumbDefaultsMigration()
            }
            let migratedOneHandAxisMapping = migratedTuning.needsOneHandAxisMappingMigration
            if migratedOneHandAxisMapping {
                migratedTuning.applyOneHandAxisMappingMigration()
            }
            let validatedTuning = migratedTuning.validated()
            let profiles = Self.validProfiles(from: decoded.zoomProfiles)
            tuning = validatedTuning
            zoomProfiles = profiles
            screenZoomShortcutsEnabled = decoded.screenZoomShortcutsEnabled ?? false
            let invalidStoredValuesWereRepaired = validatedTuning != migratedTuning
                || profiles != decoded.zoomProfiles
            let repaired = migratedMiddleThumbDefaults
                || migratedOneHandAxisMapping
                || invalidStoredValuesWereRepaired
            if invalidStoredValuesWereRepaired {
                lastValidationMessage = "Invalid stored values were replaced with safe values."
            } else if migratedOneHandAxisMapping {
                lastValidationMessage = "Gesture settings were updated for one-hand pinch control."
            } else if migratedMiddleThumbDefaults {
                lastValidationMessage = "Gesture settings were updated for middle-thumb control."
            } else {
                lastValidationMessage = nil
            }
            persistenceNeedsSynchronization = repaired
        } else {
            tuning = .safeDefaults
            zoomProfiles = []
            screenZoomShortcutsEnabled = false
            lastValidationMessage = nil
            persistenceNeedsSynchronization = true
        }
    }

    /// Writes defaults or repaired persisted values after the owning runtime is active.
    func synchronizePersistenceIfNeeded() {
        guard persistenceNeedsSynchronization else { return }
        persist()
    }

    /// Applies a complete tuning value atomically. Invalid values never become observable.
    @discardableResult
    public func setTuning(_ candidate: GestureTuning) -> Bool {
        let validated = candidate.validated()
        guard validated == candidate else {
            tuning = .safeDefaults
            configurationRevision &+= 1
            lastValidationMessage = "That combination was unsafe, so all tuning was restored to safe defaults."
            persist()
            return false
        }

        tuning = validated
        configurationRevision &+= 1
        lastValidationMessage = nil
        persist()
        return true
    }

    @discardableResult
    public func updateTuning(_ update: (inout GestureTuning) -> Void) -> Bool {
        var candidate = tuning
        update(&candidate)
        return setTuning(candidate)
    }

    @discardableResult
    public func upsertZoomProfile(_ profile: ZoomApplicationProfileSetting) -> Bool {
        let candidate = profile.normalized
        guard candidate.isValid else {
            lastValidationMessage = "Enter a display name, a bundle identifier such as com.example.app, and valid shortcut keys."
            return false
        }

        var updated = zoomProfiles.filter { $0.bundleIdentifier != candidate.bundleIdentifier }
        updated.append(candidate)
        zoomProfiles = Self.validProfiles(from: updated)
        configurationRevision &+= 1
        lastValidationMessage = nil
        persist()
        return true
    }

    public func removeZoomProfile(id: String) {
        zoomProfiles.removeAll { $0.bundleIdentifier == id }
        configurationRevision &+= 1
        lastValidationMessage = nil
        persist()
    }

    public func setScreenZoomShortcutsEnabled(_ enabled: Bool) {
        guard screenZoomShortcutsEnabled != enabled else { return }
        screenZoomShortcutsEnabled = enabled
        configurationRevision &+= 1
        lastValidationMessage = nil
        persist()
    }

    public func resetSafeDefaults() {
        tuning = .safeDefaults
        zoomProfiles = []
        screenZoomShortcutsEnabled = false
        configurationRevision &+= 1
        lastValidationMessage = nil
        persist()
    }

    private static func validProfiles(from profiles: [ZoomApplicationProfileSetting]) -> [ZoomApplicationProfileSetting] {
        var unique: [String: ZoomApplicationProfileSetting] = [:]
        for profile in profiles {
            let candidate = profile.normalized
            guard candidate.isValid else { continue }
            unique[candidate.bundleIdentifier] = candidate
        }
        return unique.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func persist() {
        let settings = PersistedSignalSettings(
            tuning: tuning,
            zoomProfiles: zoomProfiles,
            screenZoomShortcutsEnabled: screenZoomShortcutsEnabled
        )
        guard let data = try? encoder.encode(settings) else {
            lastValidationMessage = "Settings could not be encoded."
            return
        }
        defaults.set(data, forKey: Self.storageKey)
        persistenceNeedsSynchronization = false
    }
}
