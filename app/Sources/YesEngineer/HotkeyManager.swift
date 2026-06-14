import Carbon
import Foundation
import os

final class HotkeyManager {
    private let log = Logger(subsystem: "ai.yesengineer", category: "hotkey")
    private var refs: [EventHotKeyRef?] = []
    private var actionIDs: [UInt32: String] = [:]
    private var handlerRef: EventHandlerRef?
    var onFire: ((String) -> Void)?
    var onRegistrationConflict: ((HotkeySpec) -> Void)?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData = userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.fire(carbonID: hotKeyID.id)
            return noErr
        }

        InstallEventHandler(GetEventDispatcherTarget(),
                            callback,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &handlerRef)
    }

    deinit {
        unregisterAll()
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(actions: [TextAction]) {
        unregisterAll()

        var usedHotkeys = Set<String>()
        var nextID: UInt32 = 1
        for action in actions where action.enabled {
            let signature = "\(action.hotkey.modifiers):\(action.hotkey.keyCode)"
            guard !usedHotkeys.contains(signature) else {
                log.error("duplicate hotkey skipped: \(action.title, privacy: .public)")
                continue
            }
            usedHotkeys.insert(signature)

            var ref: EventHotKeyRef?
            let carbonID = EventHotKeyID(signature: HotkeyManager.fourCharCode("YEHK"), id: nextID)
            let status = RegisterEventHotKey(action.hotkey.keyCode,
                                             action.hotkey.modifiers,
                                             carbonID,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &ref)
            if status == noErr {
                refs.append(ref)
                actionIDs[nextID] = action.id
                log.info("registered hotkey \(action.hotkey.displayName, privacy: .public) for \(action.id, privacy: .public)")
                nextID += 1
            } else {
                log.error("register hotkey failed: \(action.hotkey.displayName, privacy: .public), status=\(status)")
                DispatchQueue.main.async { [weak self] in
                    self?.onRegistrationConflict?(action.hotkey)
                }
            }
        }
    }

    private func unregisterAll() {
        for ref in refs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        refs.removeAll()
        actionIDs.removeAll()
    }

    private func fire(carbonID: UInt32) {
        guard let actionID = actionIDs[carbonID] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFire?(actionID)
        }
    }

    private static func fourCharCode(_ s: String) -> OSType {
        var result: OSType = 0
        for scalar in s.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }
}
