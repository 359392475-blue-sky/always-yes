import Carbon
import XCTest
@testable import YesEngineer

final class HotkeySpecTests: XCTestCase {
    func testParsesDisplayedSymbolHotkeys() {
        XCTAssertEqual(HotkeySpec.parse("⌥⇧↩"), .confirm)
        XCTAssertEqual(HotkeySpec.parse("⌥⇧Y"), .yes)
        XCTAssertEqual(HotkeySpec.parse("⇧⌥C"), .continuePrompt)
    }

    func testParsesTextAliasesAsWholeTokens() {
        XCTAssertEqual(HotkeySpec.parse("option+shift+y"), .yes)
        XCTAssertEqual(HotkeySpec.parse("opt-shift-y"), .yes)
        XCTAssertEqual(HotkeySpec.parse("alt shift y"), .yes)
        XCTAssertEqual(HotkeySpec.parse("control+option+return"),
                       HotkeySpec(keyCode: 0x24,
                                  modifiers: HotkeyModifier.control | HotkeyModifier.option))
    }

    func testDetectsSystemLevelHotkeyConflict() throws {
        let hotkey = HotkeySpec(keyCode: 0x6F,
                                modifiers: HotkeyModifier.control
                                    | HotkeyModifier.option
                                    | HotkeyModifier.shift)
        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x59455453, id: 99)
        let status = RegisterEventHotKey(hotkey.keyCode,
                                         hotkey.modifiers,
                                         identifier,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            throw XCTSkip("Could not reserve the test shortcut: \(status)")
        }
        defer { UnregisterEventHotKey(ref) }

        XCTAssertNotNil(HotkeyConflictDetector.systemConflictMessage(for: hotkey))
    }

}
