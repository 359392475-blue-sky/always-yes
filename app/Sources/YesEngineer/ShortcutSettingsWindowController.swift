import AppKit

final class ShortcutSettingsWindowController: NSWindowController {
    private var config: AppConfig
    private var rows: [ShortcutRowView] = []
    private let rowsStack = NSStackView()
    private var autoSaveTimer: Timer?
    private var isReloading = false
    var onChange: ((AppConfig) -> Void)?
    var onOpenControlPanel: (() -> Void)?
    var onHotkeyRecordingChanged: ((Bool) -> Void)?

    init(config: AppConfig) {
        self.config = config

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 810, height: 280),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.text("Shortcuts & Input", "快捷键与输入内容")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        rowsStack.orientation = .vertical
        rowsStack.spacing = 8
        root.addArrangedSubview(rowsStack)
        reloadRows()

        let note = NSTextField(labelWithString: L10n.text(
            "Click a shortcut field or Record, then press a combination. Press Esc to cancel. Empty input sends Return only.",
            "点击快捷键框或“录制”，再按下一组快捷键；按 Esc 取消。输入内容为空时只按回车。"
        ))
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(note)

        let spacer = NSView()
        root.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let restore = NSButton(title: L10n.text("Restore Defaults", "恢复默认"), target: self, action: #selector(restoreDefaults))
        let openPanel = NSButton(title: L10n.text("Open Control Panel…", "打开控制面板…"), target: self, action: #selector(openControlPanel))
        let autoSaveLabel = NSTextField(labelWithString: L10n.text(
            "Changes are saved automatically",
            "更改会自动保存"
        ))
        autoSaveLabel.font = .systemFont(ofSize: 11)
        autoSaveLabel.textColor = .secondaryLabelColor

        let buttonSpacer = NSView()
        buttons.addArrangedSubview(restore)
        buttons.addArrangedSubview(openPanel)
        buttons.addArrangedSubview(buttonSpacer)
        buttons.addArrangedSubview(autoSaveLabel)
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(buttons)
    }

    private func reloadRows() {
        isReloading = true
        defer { isReloading = false }
        stopHotkeyRecording()
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()

        rowsStack.addArrangedSubview(makeHeaderRow())
        for action in config.textActions {
            let row = ShortcutRowView(action: action)
            row.onHotkeyRecordingChanged = { [weak self] recording in
                self?.onHotkeyRecordingChanged?(recording)
            }
            row.onChange = { [weak self] in
                self?.scheduleAutoSave()
            }
            row.onValidationRequested = { [weak self] in
                self?.commitChanges(showValidationErrors: true) ?? false
            }
            row.hotkeyValidationMessage = { [weak self, weak row] candidate in
                guard let self, let row else { return nil }
                return self.hotkeyConflictMessage(candidate, excluding: row)
            }
            rows.append(row)
            rowsStack.addArrangedSubview(row)
        }
    }

    func updateConfig(_ cfg: AppConfig) {
        config = cfg
        reloadRows()
    }

    private func makeHeaderRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let columns = [
            (L10n.text("Enabled", "启用"), 52),
            (L10n.text("Name", "名称"), 140),
            (L10n.text("Input", "输入内容"), 260),
            (L10n.text("Return", "回车"), 56),
            (L10n.text("Shortcut", "快捷键"), 190),
        ]
        for (title, width) in columns {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: CGFloat(width)).isActive = true
            row.addArrangedSubview(label)
        }
        return row
    }

    @objc private func restoreDefaults() {
        config.textActions = TextAction.defaults
        reloadRows()
        scheduleAutoSave(delay: 0)
    }

    @objc private func openControlPanel() {
        onOpenControlPanel?()
    }

    @discardableResult
    private func commitChanges(showValidationErrors: Bool = false) -> Bool {
        var nextActions: [TextAction] = []
        var seenHotkeys = Set<String>()

        for row in rows {
            guard var action = row.action() else {
                if showValidationErrors {
                    showValidationError(L10n.text("One shortcut is invalid.", "有一个快捷键格式不正确。"))
                }
                return false
            }
            if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if showValidationErrors {
                    showValidationError(L10n.text("Action names cannot be empty.", "动作名称不能为空。"))
                }
                return false
            }
            let signature = "\(action.hotkey.modifiers):\(action.hotkey.keyCode)"
            if action.enabled && seenHotkeys.contains(signature) {
                if showValidationErrors {
                    showValidationError(L10n.format(
                        "The shortcut %@ is used more than once.",
                        "快捷键 %@ 被重复使用。",
                        action.hotkey.displayName
                    ))
                }
                return false
            }
            if action.enabled {
                seenHotkeys.insert(signature)
            }
            action.input = action.input.trimmingCharacters(in: .newlines)
            nextActions.append(action)
        }

        config.textActions = nextActions
        if !nextActions.contains(where: { $0.id == config.slapActionID }) {
            config.slapActionID = nextActions.first(where: { $0.id == TextAction.defaultSlapActionID })?.id
                ?? nextActions.first?.id
                ?? TextAction.defaultSlapActionID
        }
        onChange?(config)
        return true
    }

    private func stopHotkeyRecording() {
        rows.forEach { $0.stopHotkeyRecording() }
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Shortcuts need attention", "快捷键需要处理")
        alert.informativeText = message
        alert.runModal()
    }

    private func scheduleAutoSave(delay: TimeInterval = 0.2) {
        guard !isReloading else { return }
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.commitChanges()
        }
    }

    private func hotkeyConflictMessage(_ candidate: HotkeySpec,
                                       excluding sourceRow: ShortcutRowView) -> String? {
        let duplicate = rows.contains { row in
            row !== sourceRow && row.isEnabled && row.hotkey == candidate
        }
        if duplicate {
            return L10n.format("The shortcut %@ is already assigned to another action.",
                               "快捷键 %@ 已分配给其他动作。",
                               candidate.displayName)
        }
        return HotkeyConflictDetector.systemConflictMessage(for: candidate)
    }
}

private final class ShortcutRowView: NSStackView {
    private let sourceID: String
    private let enabledBox: NSButton
    private let titleField: NSTextField
    private let inputField: NSTextField
    private let returnBox: NSButton
    private let hotkeyRecorder: HotkeyRecorderView
    var onChange: (() -> Void)?
    var onValidationRequested: (() -> Bool)?
    var hotkeyValidationMessage: ((HotkeySpec) -> String?)? {
        didSet {
            hotkeyRecorder.validationMessage = hotkeyValidationMessage
        }
    }
    var onHotkeyRecordingChanged: ((Bool) -> Void)? {
        didSet {
            hotkeyRecorder.onRecordingChanged = onHotkeyRecordingChanged
        }
    }

    var isEnabled: Bool {
        enabledBox.state == .on
    }

    var hotkey: HotkeySpec {
        hotkeyRecorder.currentHotkey()
    }

    init(action: TextAction) {
        self.sourceID = action.id
        self.enabledBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.titleField = NSTextField(string: action.title)
        self.inputField = NSTextField(string: action.input)
        self.returnBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.hotkeyRecorder = HotkeyRecorderView(hotkey: action.hotkey, width: 190)
        super.init(frame: .zero)

        orientation = .horizontal
        spacing = 8

        enabledBox.state = action.enabled ? .on : .off
        returnBox.state = action.autoPressReturn ? .on : .off
        enabledBox.target = self
        enabledBox.action = #selector(enabledChanged)
        returnBox.target = self
        returnBox.action = #selector(valueChanged)
        titleField.delegate = self
        inputField.delegate = self
        hotkeyRecorder.onHotkeyChanged = { [weak self] _ in
            self?.onChange?()
        }
        enabledBox.widthAnchor.constraint(equalToConstant: 52).isActive = true
        titleField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        inputField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        returnBox.widthAnchor.constraint(equalToConstant: 56).isActive = true

        addArrangedSubview(enabledBox)
        addArrangedSubview(titleField)
        addArrangedSubview(inputField)
        addArrangedSubview(returnBox)
        addArrangedSubview(hotkeyRecorder)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action() -> TextAction? {
        return TextAction(id: sourceID,
                          title: titleField.stringValue,
                          input: inputField.stringValue,
                          autoPressReturn: returnBox.state == .on,
                          hotkey: hotkeyRecorder.currentHotkey(),
                          enabled: enabledBox.state == .on)
    }

    func stopHotkeyRecording() {
        hotkeyRecorder.stopRecording()
    }

    @objc private func valueChanged() {
        onChange?()
    }

    @objc private func enabledChanged() {
        if onValidationRequested?() == false {
            enabledBox.state = enabledBox.state == .on ? .off : .on
        }
    }
}

extension ShortcutRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onChange?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        _ = onValidationRequested?()
    }
}

extension ShortcutSettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        autoSaveTimer?.invalidate()
        commitChanges(showValidationErrors: true)
        stopHotkeyRecording()
    }
}
