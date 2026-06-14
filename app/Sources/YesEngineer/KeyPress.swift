import AppKit
import CoreGraphics

enum KeyPress {
    static let kVKReturn: CGKeyCode = 0x24
    static let kVKV: CGKeyCode = 0x09

    static func sendEnter() -> Bool {
        postKey(kVKReturn)
    }

    static func send(text: String, pressReturn: Bool, completion: ((Bool) -> Void)? = nil) {
        if text.isEmpty {
            let ok = pressReturn ? sendEnter() : true
            completion?(ok)
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            completion?(false)
            return
        }

        let pasted = postKey(kVKV, flags: .maskCommand)
        guard pasted else {
            snapshot.restore(to: pasteboard)
            completion?(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let ok = pressReturn ? sendEnter() : true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                snapshot.restore(to: pasteboard)
                completion?(ok)
            }
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return false }
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardSnapshot {
    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(contents: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    struct Item {
        let contents: [(NSPasteboard.PasteboardType, Data)]
    }
}
