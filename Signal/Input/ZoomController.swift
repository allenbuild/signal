@preconcurrency import AppKit
import Foundation

public struct ZoomShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: InputModifierFlags

    public init(keyCode: UInt16, modifiers: InputModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var eventPair: [LowLevelInputEvent] {
        var result: [LowLevelInputEvent] = []
        var activeModifiers: InputModifierFlags = []
        let chord = SyntheticModifierKey.allCases.filter { modifiers.contains($0.flag) }

        for modifier in chord {
            activeModifiers.insert(modifier.flag)
            result.append(.key(
                keyCode: modifier.keyCode,
                isDown: true,
                modifiers: activeModifiers
            ))
        }
        result.append(.key(keyCode: keyCode, isDown: true, modifiers: modifiers))
        result.append(.key(keyCode: keyCode, isDown: false, modifiers: modifiers))
        for modifier in chord.reversed() {
            activeModifiers.remove(modifier.flag)
            result.append(.key(
                keyCode: modifier.keyCode,
                isDown: false,
                modifiers: activeModifiers
            ))
        }
        return result
    }
}

/// ANSI modifier positions. Quartz requires complete modifier down/up
/// sequences; the final release always has empty flags and therefore clears
/// the private event source before any later mouse event.
private enum SyntheticModifierKey: CaseIterable {
    case control
    case option
    case shift
    case command

    var keyCode: UInt16 {
        switch self {
        case .command: 55
        case .shift: 56
        case .option: 58
        case .control: 59
        }
    }

    var flag: InputModifierFlags {
        switch self {
        case .command: .command
        case .shift: .shift
        case .option: .option
        case .control: .control
        }
    }
}

public struct ZoomApplicationProfile: Codable, Equatable, Sendable {
    public var zoomIn: ZoomShortcut
    public var zoomOut: ZoomShortcut
    public var reset: ZoomShortcut?

    public init(zoomIn: ZoomShortcut, zoomOut: ZoomShortcut, reset: ZoomShortcut? = nil) {
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
        self.reset = reset
    }

    /// macOS Accessibility screen magnification. Unlike Command-plus/minus,
    /// these shortcuts do not change an application's document or page zoom.
    /// The user enables them in System Settings > Accessibility > Zoom.
    // ANSI equal/plus = 24 and minus = 27.
    public static let standard = Self(
        zoomIn: ZoomShortcut(keyCode: 24, modifiers: [.command, .option]),
        zoomOut: ZoomShortcut(keyCode: 27, modifiers: [.command, .option]),
        reset: nil
    )
}

public protocol FrontmostApplicationProviding: AnyObject, Sendable {
    var frontmostBundleIdentifier: String? { get }
}

public final class SystemFrontmostApplicationProvider:
    FrontmostApplicationProviding, @unchecked Sendable {

    public init() {}

    public var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

/// Queue-confined continuous-to-discrete zoom conversion. It never schedules a
/// timer and therefore cannot emit after its caller resets it.
public final class ZoomController {
    private let applicationProvider: FrontmostApplicationProviding
    private let clock: InputMonotonicClock
    private let minimumEmissionInterval: TimeInterval
    private let builtInProfiles: [String: ZoomApplicationProfile]
    private var userProfiles: [String: ZoomApplicationProfile]
    private var activeBundleIdentifier: String?
    private var hasActiveProfile = false
    private var accumulator = 0.0
    private var lastEmissionTime = -Double.infinity

    public init(
        applicationProvider: FrontmostApplicationProviding,
        clock: InputMonotonicClock,
        userProfiles: [String: ZoomApplicationProfile] = [:],
        minimumEmissionInterval: TimeInterval = 0.040
    ) {
        self.applicationProvider = applicationProvider
        self.clock = clock
        self.userProfiles = userProfiles
        self.minimumEmissionInterval = max(0, minimumEmissionInterval)
        builtInProfiles = [
            "com.apple.Safari": .standard,
            "com.apple.Preview": .standard,
            "com.google.Chrome": .standard,
            "org.mozilla.firefox": .standard
        ]
    }

    public func updateUserProfiles(_ profiles: [String: ZoomApplicationProfile]) {
        userProfiles = profiles
        reset()
    }

    public func events(
        for delta: Double,
        tuning: GestureTuning,
        physicalModifiers: InputModifierFlags
    ) -> [LowLevelInputEvent] {
        guard delta.isFinite else {
            reset()
            return []
        }
        guard physicalModifiers.isEmpty else {
            accumulator = 0
            lastEmissionTime = -Double.infinity
            return []
        }

        let bundleIdentifier = applicationProvider.frontmostBundleIdentifier
        if !hasActiveProfile {
            hasActiveProfile = true
            activeBundleIdentifier = bundleIdentifier
            accumulator = 0
            lastEmissionTime = -Double.infinity
        } else if activeBundleIdentifier != bundleIdentifier {
            // A genuine target-application change is an interaction boundary;
            // discard that one cross-application delta and re-anchor.
            activeBundleIdentifier = bundleIdentifier
            accumulator = 0
            lastEmissionTime = -Double.infinity
            return []
        }

        let threshold = tuning.zoomStepThreshold
        let maximumSteps = min(max(tuning.zoomMaximumStepsPerFrame, 1), 8)
        guard threshold.isFinite, threshold > 0, maximumSteps > 0 else { return [] }

        // GestureEngine owns continuous zoom sensitivity. Input owns only the
        // discrete shortcut threshold/rate conversion.
        accumulator += delta
        let maximumRetained = threshold * Double(maximumSteps)
        accumulator = min(max(accumulator, -maximumRetained), maximumRetained)
        let magnitude = abs(accumulator)
        guard magnitude >= threshold else { return [] }

        let now = clock.now
        guard now - lastEmissionTime >= minimumEmissionInterval else { return [] }

        // Clamp in floating point before conversion. A finite Double can still
        // exceed Int.max, and conversion would otherwise trap.
        let quotient = magnitude / threshold
        guard quotient.isFinite else {
            reset()
            return []
        }
        let fullStepCount = Int(min(quotient, Double(maximumSteps)))
        let stepCount = min(fullStepCount, maximumSteps)
        let positive = accumulator > 0
        let remainder = magnitude.truncatingRemainder(dividingBy: threshold)
        accumulator = positive ? remainder : -remainder
        lastEmissionTime = now

        let profile = profile(for: bundleIdentifier)
        let shortcut = positive ? profile.zoomIn : profile.zoomOut
        return (0..<stepCount).flatMap { _ in shortcut.eventPair }
    }

    public func resetShortcutEvents(
        physicalModifiers: InputModifierFlags
    ) -> [LowLevelInputEvent] {
        guard physicalModifiers.isEmpty else { return [] }
        return profile(for: applicationProvider.frontmostBundleIdentifier).reset?.eventPair ?? []
    }

    public func reset() {
        activeBundleIdentifier = nil
        hasActiveProfile = false
        accumulator = 0
        lastEmissionTime = -Double.infinity
    }

    private func profile(for bundleIdentifier: String?) -> ZoomApplicationProfile {
        guard let bundleIdentifier else { return .standard }
        return userProfiles[bundleIdentifier]
            ?? builtInProfiles[bundleIdentifier]
            ?? .standard
    }
}
