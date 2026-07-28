import Foundation

enum ZoomOutputPolicy {
    /// Production screen zoom never consumes persisted application shortcuts.
    /// Keeping this decision in one testable seam prevents either initial
    /// composition or later settings updates from restoring page zoom.
    static func productionProfiles(
        ignoring _: [ZoomApplicationProfileSetting]
    ) -> [String: ZoomApplicationProfile] {
        [:]
    }
}

/// Legacy settings decoder seam retained for compatibility tests. Production
/// runtime intentionally does not call this adapter because arbitrary app
/// shortcuts can change page or document zoom.
enum ZoomProfileAdapter {
    static func profiles(
        from settings: [ZoomApplicationProfileSetting]
    ) -> [String: ZoomApplicationProfile] {
        var result: [String: ZoomApplicationProfile] = [:]
        for setting in settings {
            guard let zoomIn = shortcut(from: setting.zoomIn),
                  let zoomOut = shortcut(from: setting.zoomOut) else {
                continue
            }
            result[setting.bundleIdentifier] = ZoomApplicationProfile(
                zoomIn: zoomIn,
                zoomOut: zoomOut,
                reset: setting.reset.flatMap(shortcut(from:))
            )
        }
        return result
    }

    private static func shortcut(from setting: ZoomShortcutSetting) -> ZoomShortcut? {
        guard let mapping = ZoomShortcutKeyCatalog.mapping(for: setting.keyEquivalent) else {
            return nil
        }

        var modifiers: InputModifierFlags = []
        if setting.command { modifiers.insert(.command) }
        if setting.option { modifiers.insert(.option) }
        if setting.control { modifiers.insert(.control) }
        if setting.shift || mapping.requiresShift { modifiers.insert(.shift) }
        return ZoomShortcut(keyCode: mapping.keyCode, modifiers: modifiers)
    }

}
