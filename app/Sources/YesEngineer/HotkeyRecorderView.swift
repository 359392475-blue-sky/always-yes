import AppKit

final class HotkeyRecorderView: NSStackView {
    private static weak var activeRecorder: HotkeyRecorderView?

    private let displayButton = NSButton()
    private let recordButton = NSButton()
    private var hotkey: HotkeySpec
    private var eventMonitor: Any?
    private(set) var isRecording = false

    var onRecordingChanged: ((Bool) -> Void)?
    var onHotkeyChanged: ((HotkeySpec) -> Void)?
    var validationMessage: ((HotkeySpec) -> String?)?

    init(hotkey: HotkeySpec, width: CGFloat) {
        self.hotkey = hotkey
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        widthAnchor.constraint(equalToConstant: width).isActive = true

        displayButton.title = hotkey.displayName
        displayButton.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        displayButton.alignment = .left
        displayButton.bezelStyle = .rounded
        displayButton.target = self
        displayButton.action = #selector(beginRecording)
        displayButton.toolTip = L10n.text("Click to record a new shortcut", "点击后录制新的快捷键")
        displayButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        recordButton.title = L10n.text("Record", "录制")
        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .small
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.toolTip = L10n.text("Record the next shortcut", "录制下一组快捷键")
        recordButton.widthAnchor.constraint(equalToConstant: 54).isActive = true

        addArrangedSubview(displayButton)
        addArrangedSubview(recordButton)
        setAccessibilityLabel(L10n.format("Shortcut %@", "快捷键 %@", hotkey.displayName))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopRecording()
    }

    func recordedHotkey() -> HotkeySpec {
        stopRecording()
        return hotkey
    }

    func currentHotkey() -> HotkeySpec {
        hotkey
    }

    func stopRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        HotkeyRecorderView.activeRecorder?.stopRecording()
        HotkeyRecorderView.activeRecorder = self

        isRecording = true
        displayButton.title = L10n.text("Press shortcut…", "请按快捷键…")
        displayButton.contentTintColor = .systemOrange
        recordButton.title = L10n.text("Cancel", "取消")
        onRecordingChanged?(true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            guard event.window === self.window else { return event }
            self.capture(event)
            return nil
        }
    }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            beginRecording()
        }
    }

    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 0x35 {
            stopRecording()
            return
        }

        let modifiers = Self.hotkeyModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            displayButton.title = L10n.text("Include a modifier", "请组合修饰键")
            return
        }

        let candidate = HotkeySpec(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if let message = validationMessage?(candidate) {
            NSSound.beep()
            displayButton.title = L10n.text("Shortcut unavailable", "快捷键不可用")
            showConflict(message)
            return
        }
        hotkey = candidate
        finishRecording()
        onHotkeyChanged?(hotkey)
    }

    private func finishRecording() {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        displayButton.title = hotkey.displayName
        displayButton.contentTintColor = nil
        recordButton.title = L10n.text("Record", "录制")
        setAccessibilityLabel(L10n.format("Shortcut %@", "快捷键 %@", hotkey.displayName))
        if HotkeyRecorderView.activeRecorder === self {
            HotkeyRecorderView.activeRecorder = nil
        }
        onRecordingChanged?(false)
    }

    private func showConflict(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Shortcut conflict", "快捷键冲突")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
        if isRecording {
            displayButton.title = L10n.text("Press another shortcut…", "请按其他快捷键…")
        }
    }

    private static func hotkeyModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= HotkeyModifier.command }
        if flags.contains(.shift) { modifiers |= HotkeyModifier.shift }
        if flags.contains(.option) { modifiers |= HotkeyModifier.option }
        if flags.contains(.control) { modifiers |= HotkeyModifier.control }
        return modifiers
    }
}
