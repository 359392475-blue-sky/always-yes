import AppKit
import SharedTypes
import os

final class MenuBarController: NSObject, NSMenuDelegate {
    private let log = Logger(subsystem: "ai.yesengineer", category: "menubar")
    private let store = ConfigStore()
    private let client = DaemonClient()
    private let hotkeys = HotkeyManager()
    private let feedback = FeedbackPresenter()
    private var statusItem: NSStatusItem!
    private var pulseTimer: Timer?
    private var sensitivityCommitTimer: Timer?
    private var accessibilityPromptTimer: Timer?
    private var shortcutSettings: ShortcutSettingsWindowController?
    private var settingsWindow: SettingsWindowController?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Yes Engineer")
            btn.image?.isTemplate = true
            btn.toolTip = "Yes Engineer"
        }

        // First-run install attempt; ignore failures so user can retry from menu.
        if !AppEnvironment.isUITesting, DaemonInstaller.status == .notRegistered {
            try? DaemonInstaller.install()
        }

        rebuildMenu()
        hotkeys.onFire = { [weak self] actionID in
            self?.performActionIfAllowed(actionID: actionID, source: "hotkey")
        }
        hotkeys.onRegistrationConflict = { [weak self] hotkey in
            self?.showHotkeyConflict(hotkey)
        }
        if !AppEnvironment.isUITesting {
            hotkeys.register(actions: store.config.activeHotkeyActions)
        }
        client.onSlap = { [weak self] ev in self?.handleSlap(ev) }
        client.onConnected = { [weak self] in
            guard let self = self else { return }
            self.client.push(config: self.store.config.daemonConfig())
        }
        if !AppEnvironment.isUITesting {
            client.connect()
        }

        if !AppEnvironment.isUITesting {
            updateAutoAccessibilityPrompting()
        }
    }

    func showControlPanel() {
        openControlPanel()
        guard let path = AppEnvironment.values["YES_ENGINEER_SCREENSHOT_PATH"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            do {
                try self?.settingsWindow?.writeScreenshot(to: URL(fileURLWithPath: path))
            } catch {
                self?.log.error("screenshot failed: \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let sliderItem = NSMenuItem()
        let sliderView = SensitivitySliderView(initial: store.config.minAmplitude)
        sliderView.onChange = { [weak self] v in self?.applySensitivity(v) }
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        let panel = NSMenuItem(title: L10n.text("Open Control Panel…", "打开控制面板…"),
                               action: #selector(openControlPanel),
                               keyEquivalent: ",")
        panel.target = self
        menu.addItem(panel)

        menu.addItem(NSMenuItem.separator())

        let pauseMenu = NSMenu()
        for (title, key, paused) in [
            (L10n.text("Pause everything", "全部暂停"), "all", store.config.paused),
            (L10n.text("Pause tap actions", "暂停拍击动作"), "slap", store.config.pauseSlapActions),
            (L10n.text("Pause shortcuts", "暂停快捷键"), "hotkeys", store.config.pauseHotkeys),
        ] {
            let item = NSMenuItem(title: title, action: #selector(togglePauseFlag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = paused ? .on : .off
            pauseMenu.addItem(item)
        }
        let pauseRootTitle: String
        if store.config.paused {
            pauseRootTitle = L10n.text("Pause Controls (All Paused)", "暂停控制（全部已暂停）")
        } else if store.config.pauseSlapActions || store.config.pauseHotkeys {
            pauseRootTitle = L10n.text("Pause Controls (Partially Paused)", "暂停控制（部分已暂停）")
        } else {
            pauseRootTitle = L10n.text("Pause Controls", "暂停控制")
        }
        let pauseRoot = NSMenuItem(title: pauseRootTitle, action: nil, keyEquivalent: "")
        pauseRoot.submenu = pauseMenu
        menu.addItem(pauseRoot)

        menu.addItem(NSMenuItem.separator())

        let modeMenu = NSMenu()
        for m in AppMode.allCases {
            let item = NSMenuItem(title: modeName(m), action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = (store.config.mode == m) ? .on : .off
            modeMenu.addItem(item)
        }
        let modeRoot = NSMenuItem(title: L10n.text("App Scope", "应用范围"), action: nil, keyEquivalent: "")
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        let slapMenu = NSMenu()
        for action in store.config.textActions {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(setSlapAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            item.state = (store.config.slapActionID == action.id) ? .on : .off
            slapMenu.addItem(item)
        }
        let slapRoot = NSMenuItem(title: L10n.text("Tap Action", "拍击动作"), action: nil, keyEquivalent: "")
        slapRoot.submenu = slapMenu
        menu.addItem(slapRoot)

        let shortcutsMenu = NSMenu()
        for action in store.config.textActions where action.enabled {
            let item = NSMenuItem(title: "\(action.menuTitle)  \(action.hotkey.displayName)",
                                  action: #selector(runShortcutAction(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            shortcutsMenu.addItem(item)
        }
        shortcutsMenu.addItem(NSMenuItem.separator())
        let editShortcuts = NSMenuItem(title: L10n.text("Edit Shortcuts & Input…", "编辑快捷键与输入内容…"),
                                       action: #selector(openShortcutSettings),
                                       keyEquivalent: ",")
        editShortcuts.target = self
        shortcutsMenu.addItem(editShortcuts)
        let shortcutsRoot = NSMenuItem(title: L10n.text("Shortcuts", "快捷键"), action: nil, keyEquivalent: "")
        shortcutsRoot.submenu = shortcutsMenu
        menu.addItem(shortcutsRoot)

        let feedbackMenu = NSMenu()
        for mode in FeedbackMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(setFeedbackMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (store.config.feedbackMode == mode) ? .on : .off
            feedbackMenu.addItem(item)
        }
        let feedbackRoot = NSMenuItem(title: L10n.text("Feedback", "执行反馈"), action: nil, keyEquivalent: "")
        feedbackRoot.submenu = feedbackMenu
        menu.addItem(feedbackRoot)

        menu.addItem(NSMenuItem.separator())

        let install = NSMenuItem(title: L10n.format("Daemon: %@", "守护进程：%@", DaemonInstaller.statusDescription),
                                  action: #selector(reinstallDaemon), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        let axOK = Permissions.isAccessibilityTrusted
        let axItem = NSMenuItem(title: L10n.format(
            "Accessibility: %@",
            "辅助功能：%@",
            axOK
                ? L10n.text("Granted", "已授权")
                : L10n.text("Not granted (click to request)", "未授权（点此申请）")
        ),
                                action: #selector(requestAX), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: L10n.text("Quit Yes Engineer", "退出 Yes Engineer"),
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func applySensitivity(_ v: Double) {
        // Debounce save+push: only fire 200ms after the last drag tick to
        // avoid log spam and dozens of disk writes per drag.
        sensitivityCommitTimer?.invalidate()
        sensitivityCommitTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            var cfg = self.store.config
            cfg.minAmplitude = v
            self.applyConfig(cfg, feedbackMessage: nil)
        }
    }

    private func applyConfig(_ cfg: AppConfig,
                             feedbackMessage: String? = nil,
                             skipSettingsWindow: Bool = false,
                             skipShortcutWindow: Bool = false) {
        store.save(cfg)
        if !AppEnvironment.isUITesting {
            client.push(config: cfg.daemonConfig())
            hotkeys.register(actions: cfg.activeHotkeyActions)
            updateAutoAccessibilityPrompting()
        }
        rebuildMenu()
        if !skipShortcutWindow {
            shortcutSettings?.updateConfig(cfg)
        }
        if !skipSettingsWindow {
            settingsWindow?.updateConfig(cfg)
        }
        if let feedbackMessage = feedbackMessage {
            showFeedback(feedbackMessage)
        }
    }

    private func modeName(_ m: AppMode) -> String {
        switch m {
        case .whitelist: return L10n.text("Whitelist (AI coding apps)", "白名单（AI 编程应用）")
        case .global: return L10n.text("All apps", "所有应用")
        case .off: return L10n.text("Off (log only)", "关闭（仅记录）")
        }
    }

    private func updateAutoAccessibilityPrompting() {
        accessibilityPromptTimer?.invalidate()
        accessibilityPromptTimer = nil

        guard store.config.autoRequestAccessibility, !Permissions.isAccessibilityTrusted else { return }
        Permissions.requestAccessibilityIfNeeded()
        accessibilityPromptTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            guard self.store.config.autoRequestAccessibility, !Permissions.isAccessibilityTrusted else {
                timer.invalidate()
                self.accessibilityPromptTimer = nil
                return
            }
            Permissions.requestAccessibilityIfNeeded()
            self.settingsWindow?.refreshStatus()
            self.rebuildMenu()
        }
    }

    // MARK: Slap handling

    private func handleSlap(_ ev: SlapEvent) {
        log.info("slap: amp=\(ev.amplitude, format: .fixed(precision: 4))")
        pulse()

        let cfg = store.config
        if cfg.isSlapPaused { return }
        switch cfg.mode {
        case .whitelist:
            let bid = Frontmost.bundleID()
            guard cfg.effectiveApps.contains(bid) else {
                log.info("ignored: front=\(bid, privacy: .public) not whitelisted")
                return
            }
            performAction(id: cfg.slapActionID)
        case .global:
            performAction(id: cfg.slapActionID)
        case .off:
            log.info("slap received but mode=off (front=\(Frontmost.bundleID(), privacy: .public))")
        }
    }

    private func performActionIfAllowed(actionID: String, source: String) {
        let cfg = store.config
        if cfg.isHotkeyPaused {
            log.info("ignored \(source, privacy: .public): paused")
            return
        }
        switch cfg.mode {
        case .whitelist:
            let bid = Frontmost.bundleID()
            guard cfg.effectiveApps.contains(bid) else {
                log.info("ignored \(source, privacy: .public): front=\(bid, privacy: .public) not whitelisted")
                return
            }
            performAction(id: actionID)
        case .global:
            performAction(id: actionID)
        case .off:
            log.info("ignored \(source, privacy: .public): mode=off")
        }
    }

    private func performAction(id: String) {
        guard Permissions.isAccessibilityTrusted else {
            log.error("accessibility not trusted; ignoring action")
            return
        }
        let action = store.config.action(id: id)
        KeyPress.send(text: action.input, pressReturn: action.autoPressReturn) { [weak self] ok in
            guard let self = self else { return }
            self.log.info("performAction \(action.id, privacy: .public)=\(ok, privacy: .public)")
            if ok {
                self.showFeedback(self.feedbackMessage(for: action))
            }
        }
    }

    private func pulse() {
        guard let btn = statusItem.button else { return }
        btn.alphaValue = 0.3
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            DispatchQueue.main.async { btn.alphaValue = 1.0 }
        }
    }

    // MARK: Menu actions

    @objc private func togglePauseFlag(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var cfg = store.config
        switch key {
        case "all":
            cfg.paused.toggle()
        case "slap":
            cfg.pauseSlapActions.toggle()
        case "hotkeys":
            cfg.pauseHotkeys.toggle()
        default:
            return
        }
        applyConfig(cfg)
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let m = AppMode(rawValue: raw) else { return }
        if m == .global, store.config.mode != .global {
            let proceed = confirmGlobalMode()
            if !proceed { return }
        }
        var cfg = store.config
        cfg.mode = m
        applyConfig(cfg)
    }

    private func confirmGlobalMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.text(
            "Trigger in every app?",
            "在所有应用里触发？"
        )
        alert.informativeText = L10n.text(
            "Yes Engineer will send Return (and any configured text) to whatever app is in the foreground. This can submit half-typed messages, send chat replies, or trigger destructive actions in any app. Use the Whitelist mode if you only want AI coding apps to respond.",
            "启用后，Yes 工程师会在任何前台应用里发送回车（以及配置的输入内容）。这可能提交未写完的消息、发出聊天回复，或在任意应用里触发不可撤销的操作。如果只想让 AI 编程应用响应，请改用“白名单”模式。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("Enable All apps", "启用所有应用"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func setSlapAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var cfg = store.config
        cfg.slapActionID = id
        applyConfig(cfg)
    }

    @objc private func setFeedbackMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = FeedbackMode(rawValue: raw) else { return }
        var cfg = store.config
        cfg.feedbackMode = mode
        applyConfig(cfg, feedbackMessage: L10n.format("Feedback: %@", "执行反馈：%@", mode.menuTitle))
    }

    @objc private func runShortcutAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        performActionIfAllowed(actionID: id, source: "menu")
    }

    @objc private func openShortcutSettings() {
        let controller = ShortcutSettingsWindowController(config: store.config)
        controller.onChange = { [weak self, weak controller] cfg in
            guard let self = self else { return }
            self.applyConfig(cfg, skipShortcutWindow: controller != nil)
        }
        controller.onOpenControlPanel = { [weak self] in
            self?.openControlPanel()
        }
        controller.onHotkeyRecordingChanged = { [weak self] recording in
            self?.setHotkeyRecording(recording)
        }
        shortcutSettings = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openControlPanel() {
        let controller = settingsWindow ?? SettingsWindowController(config: store.config, configURL: store.url)
        controller.onChange = { [weak self, weak controller] cfg in
            self?.applyConfig(cfg, skipSettingsWindow: controller != nil)
        }
        controller.onRequestAccessibility = { [weak self] in
            self?.requestAX()
            self?.settingsWindow?.refreshStatus()
        }
        controller.onReinstallDaemon = { [weak self] in
            self?.reinstallDaemon()
            self?.settingsWindow?.refreshStatus()
        }
        controller.onHotkeyRecordingChanged = { [weak self] recording in
            self?.setHotkeyRecording(recording)
        }
        settingsWindow = controller
        controller.updateConfig(store.config)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setHotkeyRecording(_ recording: Bool) {
        if !AppEnvironment.isUITesting {
            hotkeys.register(actions: recording ? [] : store.config.activeHotkeyActions)
        }
    }

    private func showFeedback(_ message: String) {
        feedback.show(message, mode: store.config.feedbackMode, statusItem: statusItem)
    }

    private func feedbackMessage(for action: TextAction) -> String {
        let text = action.input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return action.autoPressReturn
                ? L10n.text("Done: pressed Return", "已执行：按回车")
                : L10n.format("Done: %@", "已执行：%@", action.title)
        }
        let preview = text.count > 28 ? "\(text.prefix(28))…" : text
        if action.autoPressReturn {
            return L10n.format("Done: typed %@ and pressed Return", "已执行：输入 %@ 并回车", preview)
        }
        return L10n.format("Done: typed %@", "已执行：输入 %@", preview)
    }

    @objc private func requestAX() {
        if !Permissions.requestAccessibility(prompt: true) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        rebuildMenu()
    }

    @objc private func reinstallDaemon() {
        do {
            try DaemonInstaller.install()
            client.connect()
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.text("Daemon installation failed", "守护进程安装失败")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showHotkeyConflict(_ hotkey: HotkeySpec) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Shortcut conflict", "快捷键冲突")
        alert.informativeText = L10n.format(
            "The shortcut %@ could not be registered because macOS or another app is already using it.",
            "快捷键 %@ 无法注册，因为 macOS 或其他应用已在使用它。",
            hotkey.displayName
        )
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
