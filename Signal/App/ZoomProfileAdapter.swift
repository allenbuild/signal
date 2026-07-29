import Foundation

enum ZoomOutputPolicy {
    /// Production zoom is application-aware. User profiles take precedence;
    /// `ZoomController` supplies frontmost-app defaults and a Command +/-/0
    /// fallback when no explicit profile exists.
    static func productionProfiles(
        ignoring settings: [ZoomApplicationProfileSetting]
    ) -> [String: ZoomApplicationProfile] {
        ZoomProfileAdapter.profiles(from: settings)
    }
}

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
