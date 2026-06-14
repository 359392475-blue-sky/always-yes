import Carbon

enum HotkeyConflictDetector {
    static func systemConflictMessage(for hotkey: HotkeySpec) -> String? {
        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: fourCharCode("YECK"), id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode,
                                         hotkey.modifiers,
                                         identifier,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            if let ref {
                UnregisterEventHotKey(ref)
            }
            return nil
        }

        if status == eventHotKeyExistsErr {
            return L10n.format("The shortcut %@ is already used by macOS or another app.",
                               "快捷键 %@ 已被 macOS 或其他应用占用。",
                               hotkey.displayName)
        }
        return L10n.format("The shortcut %@ cannot be registered (error %d).",
                           "快捷键 %@ 无法注册（错误 %d）。",
                           hotkey.displayName,
                           status)
    }

    private static func fourCharCode(_ value: String) -> OSType {
        value.unicodeScalars.prefix(4).reduce(0) { ($0 << 8) + OSType($1.value) }
    }
}
