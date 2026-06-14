import AppKit

final class SettingsWindowController: NSWindowController {
    private enum Layout {
        static let windowSize = NSSize(width: 820, height: 680)
        static let minWindowSize = NSSize(width: 720, height: 560)
        static let contentInset: CGFloat = 28
        static let sectionSpacing: CGFloat = 20
        static let rowSpacing: CGFloat = 12
        static let labelWidth: CGFloat = 120
        static let contentWidth: CGFloat = 680
    }

    private var config: AppConfig
    private let configURL: URL
    private var actionRows: [SettingsActionRowView] = []
    private var autoSaveTimer: Timer?
    private var isLoadingControls = false

    private let sensitivitySlider = NSSlider(value: 0.144,
                                             minValue: SensitivitySliderView.minValue,
                                             maxValue: SensitivitySliderView.maxValue,
                                             target: nil,
                                             action: nil)
    private let sensitivityValue = NSTextField(labelWithString: "")
    private let cooldownField = NSTextField(string: "")
    private let cooldownStepper = NSStepper()
    private let pauseAllSwitch = NSButton(checkboxWithTitle: L10n.text("Pause everything", "全部暂停"), target: nil, action: nil)
    private let pauseSlapSwitch = NSButton(checkboxWithTitle: L10n.text("Pause tap actions", "暂停拍击动作"), target: nil, action: nil)
    private let pauseHotkeysSwitch = NSButton(checkboxWithTitle: L10n.text("Pause shortcuts", "暂停快捷键"), target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: [
        L10n.text("Whitelist", "白名单"),
        L10n.text("All apps", "所有应用"),
        L10n.text("Off", "关闭"),
    ],
                                                  trackingMode: .selectOne,
                                                  target: nil,
                                                  action: nil)
    private let modeControlInScope = NSSegmentedControl(labels: [
        L10n.text("Whitelist", "白名单"),
        L10n.text("All apps", "所有应用"),
        L10n.text("Off", "关闭"),
    ],
                                                        trackingMode: .selectOne,
                                                        target: nil,
                                                        action: nil)
    private let slapActionPopup = NSPopUpButton()
    private let feedbackControl = NSSegmentedControl(labels: FeedbackMode.allCases.map(\.menuTitle),
                                                     trackingMode: .selectOne,
                                                     target: nil,
                                                     action: nil)
    private let actionRowsStack = NSStackView()
    private let deleteActionButton = NSButton(title: L10n.text("Delete selected", "删除所选"), target: nil, action: nil)
    private let daemonStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let autoRequestAXSwitch = NSButton(checkboxWithTitle: L10n.text("Prompt for Accessibility permission automatically", "自动提示辅助功能授权"), target: nil, action: nil)
    private let configPathButton = NSButton()
    private let pageControl = NSSegmentedControl(labels: [
        L10n.text("General", "通用"),
        L10n.text("App Scope", "应用范围"),
        L10n.text("Actions", "动作"),
    ],
                                                  trackingMode: .selectOne,
                                                  target: nil,
                                                  action: nil)
    private let pageContainer = NSView()
    private var pageViews: [NSView] = []

    var onChange: ((AppConfig) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onReinstallDaemon: (() -> Void)?
    var onHotkeyRecordingChanged: ((Bool) -> Void)?

    init(config: AppConfig, configURL: URL) {
        self.config = config
        self.configURL = configURL

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Layout.windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.text("Yes Engineer Settings", "Yes Engineer 设置")
        window.isReleasedWhenClosed = false
        window.minSize = Layout.minWindowSize
        super.init(window: window)
        window.delegate = self
        window.registerForDraggedTypes([.fileURL])

        buildUI()
        loadConfigIntoControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateConfig(_ cfg: AppConfig) {
        config = cfg
        loadConfigIntoControls()
    }

    func refreshStatus() {
        daemonStatusLabel.stringValue = L10n.format("Daemon: %@", "守护进程 %@", DaemonInstaller.statusDescription)
        accessibilityStatusLabel.stringValue = L10n.format(
            "Accessibility: %@",
            "辅助功能 %@",
            Permissions.isAccessibilityTrusted
                ? L10n.text("Granted", "已授权")
                : L10n.text("Not granted", "未授权")
        )
        daemonStatusLabel.textColor = .secondaryLabelColor
        accessibilityStatusLabel.textColor = Permissions.isAccessibilityTrusted ? .systemGreen : .systemOrange
        daemonStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        accessibilityStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
    }

    func writeScreenshot(to url: URL) throws {
        guard let view = window?.contentView else {
            throw CocoaError(.fileWriteUnknown)
        }
        window?.makeFirstResponder(nil)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        root.addArrangedSubview(makeHeader())
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(makePagedArea())
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(makeBottomBar())
    }

    private func makeHeader() -> NSView {
        let wrapper = NSView()
        wrapper.heightAnchor.constraint(equalToConstant: 92).isActive = true

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)

        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.tap.fill",
                                             accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
            ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)

        let title = NSTextField(labelWithString: "Yes Engineer")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: L10n.text(
            "Manage taps, shortcuts, and the AI coding app scope.",
            "管理拍击、快捷键和 AI 编程应用范围。"
        ))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitle)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            content.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            title.bottomAnchor.constraint(equalTo: content.centerYAnchor, constant: -2),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: content.centerYAnchor, constant: 4),
        ])

        return wrapper
    }

    private func makePagedArea() -> NSView {
        let wrapper = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16,
                                        left: Layout.contentInset,
                                        bottom: 14,
                                        right: Layout.contentInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        pageControl.segmentStyle = .rounded
        pageControl.selectedSegment = AppEnvironment.requestedSettingsPage
        pageControl.target = self
        pageControl.action = #selector(pageChanged)
        for i in 0..<pageControl.segmentCount {
            pageControl.setWidth(120, forSegment: i)
        }
        let pageControlRow = NSView()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControlRow.addSubview(pageControl)
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: pageControlRow.centerXAnchor),
            pageControl.topAnchor.constraint(equalTo: pageControlRow.topAnchor),
            pageControl.bottomAnchor.constraint(equalTo: pageControlRow.bottomAnchor),
        ])
        stack.addArrangedSubview(pageControlRow)

        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(pageContainer)

        let generalPage = makeScrollContent([makeAccessSection(), makeDetectionSection()])
        let appScopePage = makeScrollContent(makeAppScopeSections())
        let actionsPage = makeScrollContent([makeActionsSection()])
        pageViews = [generalPage, appScopePage, actionsPage]
        for page in pageViews {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            pageContainer.widthAnchor.constraint(equalTo: wrapper.widthAnchor, constant: -Layout.contentInset * 2),
        ])
        updateVisiblePage()
        return wrapper
    }

    private func makeScrollContent(_ sections: [NSView]) -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .left
        stack.spacing = Layout.sectionSpacing
        stack.edgeInsets = NSEdgeInsets(top: 4,
                                        left: 0,
                                        bottom: Layout.contentInset,
                                        right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        for section in sections {
            stack.addArrangedSubview(section)
        }

        return scrollView
    }

    private func makeBottomBar() -> NSView {
        let wrapper = NSView()
        wrapper.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let configLabel = NSTextField(labelWithString: L10n.text("Configuration", "配置文件"))
        configLabel.font = .systemFont(ofSize: 11)
        configLabel.textColor = .tertiaryLabelColor
        configLabel.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(configLabel)

        let abbreviatedPath = AppEnvironment.isUITesting
            ? "~/Library/Application Support/YesEngineer/config.json"
            : (configURL.path as NSString).abbreviatingWithTildeInPath
        configPathButton.title = abbreviatedPath
        configPathButton.font = .systemFont(ofSize: 11)
        configPathButton.contentTintColor = .linkColor
        configPathButton.isBordered = false
        configPathButton.bezelStyle = .inline
        configPathButton.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        configPathButton.imagePosition = .imageLeading
        configPathButton.imageHugsTitle = true
        configPathButton.target = self
        configPathButton.action = #selector(revealConfigFile)
        configPathButton.toolTip = L10n.format("Reveal %@ in Finder", "在访达中显示 %@", configURL.path)
        configPathButton.setAccessibilityLabel(L10n.text("Reveal configuration file in Finder", "在访达中显示配置文件"))
        configPathButton.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(configPathButton)

        let autoSaveLabel = NSTextField(labelWithString: L10n.text(
            "Changes are saved automatically",
            "更改会自动保存"
        ))
        autoSaveLabel.font = .systemFont(ofSize: 11)
        autoSaveLabel.textColor = .secondaryLabelColor
        let restore = NSButton(title: L10n.text("Restore Defaults", "恢复默认"), target: self, action: #selector(restoreDefaults))
        let close = NSButton(title: L10n.text("Close", "关闭"), target: self, action: #selector(closePanel))

        let buttons = NSStackView(views: [autoSaveLabel, restore, close])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(buttons)

        NSLayoutConstraint.activate([
            configLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Layout.contentInset),
            configLabel.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),

            configPathButton.leadingAnchor.constraint(equalTo: configLabel.trailingAnchor, constant: 6),
            configPathButton.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            configPathButton.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -16),

            buttons.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -Layout.contentInset),
            buttons.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])

        return wrapper
    }

    private func makeAccessSection() -> NSView {
        let reinstall = NSButton(title: L10n.text("Reinstall Daemon", "重新安装守护进程"), target: self, action: #selector(reinstallDaemon))
        let requestAX = NSButton(title: L10n.text("Request Accessibility", "申请辅助功能权限"), target: self, action: #selector(requestAccessibility))
        styleSwitch(autoRequestAXSwitch)
        autoRequestAXSwitch.target = self
        autoRequestAXSwitch.action = #selector(controlChanged)

        let rows = [
            formRow(L10n.text("Accessibility", "辅助功能"),
                    horizontalStack([accessibilityStatusLabel, requestAX], spacing: 8),
                    help: L10n.text(
                        "Tap actions and shortcuts cannot simulate input until permission is granted.",
                        "未授权时，拍击和快捷键不会模拟输入。应用默认会自动提示完成授权。"
                    )),
            formRow(L10n.text("Automatic prompt", "自动提示"),
                    autoRequestAXSwitch,
                    help: L10n.text(
                        "Keep prompting until permission is granted or this option is turned off.",
                        "默认开启。应用会定时提示辅助功能授权，直到用户完成授权或关闭此开关。"
                    )),
            formRow(L10n.text("Daemon", "守护进程"),
                    horizontalStack([daemonStatusLabel, reinstall], spacing: 8)),
        ]
        return section(title: L10n.text("Permissions & Status", "权限与状态"), rows: rows)
    }

    private func makeDetectionSection() -> NSView {
        styleTextField(cooldownField, width: 72, alignment: .left)
        cooldownStepper.minValue = 100
        cooldownStepper.maxValue = 5000
        cooldownStepper.increment = 50
        cooldownStepper.target = self
        cooldownStepper.action = #selector(cooldownStepperChanged)
        cooldownField.delegate = self

        sensitivitySlider.isContinuous = true
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(sensitivityChanged)
        sensitivitySlider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        sensitivityValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sensitivityValue.textColor = .secondaryLabelColor
        sensitivityValue.alignment = .left
        sensitivityValue.widthAnchor.constraint(equalToConstant: 72).isActive = true

        modeControl.segmentStyle = .rounded
        feedbackControl.segmentStyle = .rounded
        modeControl.target = self
        modeControl.action = #selector(controlChanged)
        feedbackControl.target = self
        feedbackControl.action = #selector(controlChanged)
        for i in 0..<modeControl.segmentCount {
            modeControl.setWidth(116, forSegment: i)
        }
        for i in 0..<feedbackControl.segmentCount {
            feedbackControl.setWidth(86, forSegment: i)
        }

        [pauseAllSwitch, pauseSlapSwitch, pauseHotkeysSwitch].forEach {
            styleSwitch($0)
            $0.target = self
            $0.action = #selector(controlChanged)
        }

        let sensitivityContent = verticalStack([
            horizontalStack([sensitivitySlider, sensitivityValue], spacing: 10),
            helpLabel(L10n.text(
                "Lower values trigger more easily; higher values require a stronger tap.",
                "数值越低越容易触发；数值越高越需要明显拍击。"
            )),
        ], spacing: 4)

        let cooldownContent = horizontalStack([
            cooldownField,
            suffixLabel(L10n.text("ms", "毫秒")),
            cooldownStepper,
        ], spacing: 8)

        let pauseContent = verticalStack([
            pauseAllSwitch,
            pauseSlapSwitch,
            pauseHotkeysSwitch,
            helpLabel(L10n.text(
                "Pause everything, or temporarily pause only taps or shortcuts.",
                "全部暂停会同时停止拍击动作和快捷键；单独暂停适合临时保留另一种触发方式。"
            )),
        ], spacing: 8)

        let rows = [
            formRow(L10n.text("Sensitivity", "灵敏度"), sensitivityContent),
            formRow(L10n.text("Cooldown", "冷却时间"), cooldownContent),
            formRow(L10n.text("Pause controls", "暂停控制"), pauseContent),
            formRow(L10n.text("App scope", "应用范围"),
                    modeControl,
                    help: L10n.text(
                        "Whitelist fires only in apps you enable. All apps fires everywhere (can submit half-typed messages in any app). Off logs taps but sends nothing. Open the App Scope tab to manage the list.",
                        "白名单模式仅在启用的应用里触发。所有应用模式会在任何前台应用里触发（可能误提交未写完的消息）。关闭模式只记录拍击，不发送任何按键。打开“应用范围”标签页可管理列表。"
                    )),
            formRow(L10n.text("Feedback", "执行反馈"), feedbackControl),
        ]

        return section(title: L10n.text("Triggers & Behavior", "触发与行为"), rows: rows)
    }

    private func makeActionsSection() -> NSView {
        slapActionPopup.controlSize = .regular
        slapActionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        slapActionPopup.target = self
        slapActionPopup.action = #selector(slapActionChanged)

        actionRowsStack.orientation = .vertical
        actionRowsStack.spacing = 0
        deleteActionButton.target = self
        deleteActionButton.action = #selector(deleteSelectedAction)

        let addAction = NSButton(title: L10n.text("Add Action", "新增动作"), target: self, action: #selector(addAction))
        let restore = NSButton(title: L10n.text("Restore Default Actions", "恢复默认动作"), target: self, action: #selector(restoreDefaultActions))
        let rows = [
            formRow(L10n.text("Run on tap", "拍击时执行"), slapActionPopup),
            fullWidthRow(actionRowsStack),
            fullWidthRow(horizontalStack([addAction, deleteActionButton, restore, flexibleSpacer()], spacing: 8)),
            fullWidthRow(helpLabel(L10n.text(
                "Click a shortcut field or Record, then press a combination. Press Esc to cancel. Empty input sends Return only.",
                "点击快捷键框或“录制”，再按下一组组合键；按 Esc 取消。输入内容为空时只按回车。"
            ))),
        ]
        return section(title: L10n.text("Automation Actions", "自动化动作"), rows: rows)
    }

    // MARK: - App Scope page

    private weak var appScopeListStack: NSStackView?
    private weak var appScopeEmptyLabel: NSTextField?
    private var appScopeCategoryExpanded: [WhitelistEntry.Category: Bool] = [
        .terminal: true, .aiEditor: true, .editor: true,
    ]

    private func makeAppScopeSections() -> [NSView] {
        modeControlInScope.segmentStyle = .rounded
        modeControlInScope.target = self
        modeControlInScope.action = #selector(modeControlChanged)
        for i in 0..<modeControlInScope.segmentCount {
            modeControlInScope.setWidth(112, forSegment: i)
        }

        let rows: [NSView] = [
            formRow(L10n.text("Mode", "模式"), modeControlInScope,
                    help: L10n.text(
                        "Whitelist fires only in apps you enable below. All apps fires everywhere (can submit half-typed messages in any app). Off logs taps but sends nothing.",
                        "白名单模式仅在下方启用的应用里触发。所有应用模式会在任何前台应用里触发（可能误提交未写完的消息）。关闭模式只记录拍击，不发送任何按键。"
                    )),
            self.makeAppScopeListSection(),
            self.makeAppScopeCustomSection(),
        ]
        return rows
    }

    private func makeAppScopeListSection() -> NSView {
        // Build a section manually so the list can be re-rendered when the
        // user toggles entries.
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .left
        outer.spacing = 8
        outer.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let title = NSTextField(labelWithString: L10n.text(
            "Built-in AI coding apps",
            "内置 AI 编程应用"
        ))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        outer.addArrangedSubview(title)

        let group = NSBox()
        group.boxType = .custom
        group.borderWidth = 1
        group.cornerRadius = 10
        group.borderColor = .separatorColor
        group.fillColor = .controlBackgroundColor
        group.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 8, right: 12)
        appScopeListStack = listStack

        listContainer.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
        ])

        if let contentView = group.contentView {
            contentView.addSubview(listContainer)
            NSLayoutConstraint.activate([
                listContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
                listContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
                listContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
                listContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            ])
        }
        outer.addArrangedSubview(group)

        // Render initially after the view is in the hierarchy.
        DispatchQueue.main.async { [weak self] in
            self?.reloadAppScopeList()
        }
        return outer
    }

    private func makeAppScopeCustomSection() -> NSView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .left
        outer.spacing = 8
        outer.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let title = NSTextField(labelWithString: L10n.text(
            "Custom apps",
            "自定义应用"
        ))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        outer.addArrangedSubview(title)

        let group = NSBox()
        group.boxType = .custom
        group.borderWidth = 1
        group.cornerRadius = 10
        group.borderColor = .separatorColor
        group.fillColor = .controlBackgroundColor
        group.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .width
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let empty = NSTextField(labelWithString: L10n.text(
            "No custom apps yet. Add your terminals, editors, or chat tools below.",
            "还没有自定义应用。在下方添加你的终端、编辑器或聊天工具。"
        ))
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .tertiaryLabelColor
        empty.isHidden = true
        appScopeEmptyLabel = empty
        inner.addArrangedSubview(empty)

        let customStack = NSStackView()
        customStack.orientation = .vertical
        customStack.alignment = .width
        customStack.spacing = 6
        customStack.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(customStack)
        appScopeCustomStack = customStack

        let addManual = NSButton(title: L10n.text("Add by bundle ID…", "按 Bundle ID 添加…"),
                                 target: self, action: #selector(addCustomAppManually))
        let addFront = NSButton(title: L10n.text("Add current foreground app", "添加当前前台应用"),
                                target: self, action: #selector(addCustomAppFromFrontmost))
        let dropHint = NSTextField(labelWithString: L10n.text(
            "Tip: drag a .app from Finder onto this panel to add it.",
            "提示：把 .app 从访达拖到这个面板即可添加。"
        ))
        dropHint.font = .systemFont(ofSize: 11)
        dropHint.textColor = .tertiaryLabelColor

        let buttonRow = NSStackView(views: [addManual, addFront, flexibleSpacer()])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        inner.addArrangedSubview(buttonRow)
        inner.addArrangedSubview(dropHint)

        if let contentView = group.contentView {
            contentView.addSubview(inner)
            NSLayoutConstraint.activate([
                inner.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                inner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                inner.topAnchor.constraint(equalTo: contentView.topAnchor),
                inner.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        outer.addArrangedSubview(group)

        DispatchQueue.main.async { [weak self] in
            self?.reloadAppScopeCustomList()
        }
        return outer
    }

    private weak var appScopeCustomStack: NSStackView?

    private func reloadAppScopeList() {
        guard let stack = appScopeListStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for category in WhitelistEntry.Category.allCases {
            let header = makeCategoryHeader(category: category)
            stack.addArrangedSubview(header)
            if appScopeCategoryExpanded[category] ?? true {
                let entries = WhitelistCatalog.entries.filter { $0.category == category }
                for (idx, entry) in entries.enumerated() {
                    let row = makeWhitelistRow(entry: entry)
                    stack.addArrangedSubview(row)
                    if idx < entries.count - 1 {
                        let sep = makeInsetSeparator()
                        sep.widthAnchor.constraint(equalToConstant: Layout.contentWidth - 64).isActive = true
                        stack.addArrangedSubview(sep)
                    }
                }
            }
            stack.addArrangedSubview(makeInsetSeparator())
        }
    }

    private func makeCategoryHeader(category: WhitelistEntry.Category) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false

        let expanded = appScopeCategoryExpanded[category] ?? true
        let chevron = NSImageView(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                                  accessibilityDescription: nil) ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let label = NSTextField(labelWithString: category.displayName)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.drawsBackground = true
        label.backgroundColor = .clear

        let count = WhitelistCatalog.entries.filter { $0.category == category }.count
        let countLabel = NSTextField(labelWithString: "(\(count))")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(chevron)
        row.addArrangedSubview(label)
        row.addArrangedSubview(countLabel)
        row.addArrangedSubview(spacer)

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleCategory(_:)))
        click.buttonMask = 0x1
        let view = ClickableContainer()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
        view.layer?.cornerRadius = 4
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
        ])
        view.addGestureRecognizer(click)
        view.representedCategory = category
        return view
    }

    private func makeWhitelistRow(entry: WhitelistEntry) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.alignment = .firstBaseline  // for label baselines
        row.distribution = .fill
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 6, left: 24, bottom: 6, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        // Fixed-width checkbox column so the display name column lines up.
        let checkbox = NSButton(checkboxWithTitle: entry.displayName,
                                target: self, action: #selector(toggleWhitelistEntry(_:)))
        checkbox.state = config.enabledDefaultApps.contains(entry.bundleID) ? .on : .off
        checkbox.identifier = NSUserInterfaceItemIdentifier(entry.bundleID)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.widthAnchor.constraint(equalToConstant: 200).isActive = true

        // Fixed-width bundle ID column for the same reason.
        let bid = NSTextField(labelWithString: entry.bundleID)
        bid.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bid.textColor = .tertiaryLabelColor
        bid.translatesAutoresizingMaskIntoConstraints = false
        bid.widthAnchor.constraint(equalToConstant: 280).isActive = true
        bid.lineBreakMode = .byTruncatingMiddle

        let noteText = entry.note ?? ""
        let note = NSTextField(labelWithString: noteText)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.isHidden = noteText.isEmpty
        note.translatesAutoresizingMaskIntoConstraints = false
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(bid)
        row.addArrangedSubview(note)
        return row
    }

    private func reloadAppScopeCustomList() {
        guard let stack = appScopeCustomStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        appScopeEmptyLabel?.isHidden = !config.customApps.isEmpty
        for (idx, app) in config.customApps.enumerated() {
            let row = makeCustomAppRow(app: app)
            stack.addArrangedSubview(row)
            if idx < config.customApps.count - 1 {
                let sep = makeInsetSeparator()
                sep.widthAnchor.constraint(equalToConstant: Layout.contentWidth - 64).isActive = true
                stack.addArrangedSubview(sep)
            }
        }
    }

    private func makeCustomAppRow(app: CustomApp) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let name = NSTextField(labelWithString: app.displayName)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bid = NSTextField(labelWithString: app.bundleID)
        bid.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bid.textColor = .secondaryLabelColor
        bid.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let remove = NSButton(title: L10n.text("Remove", "移除"),
                              target: self, action: #selector(removeCustomApp(_:)))
        remove.bezelStyle = .inline
        remove.contentTintColor = .systemRed
        remove.identifier = NSUserInterfaceItemIdentifier(app.id)

        row.addArrangedSubview(name)
        row.addArrangedSubview(bid)
        row.addArrangedSubview(flexibleSpacer())
        row.addArrangedSubview(remove)
        return row
    }

    @objc private func toggleCategory(_ gr: NSClickGestureRecognizer) {
        guard let view = gr.view as? ClickableContainer,
              let cat = view.representedCategory else { return }
        appScopeCategoryExpanded[cat] = !(appScopeCategoryExpanded[cat] ?? true)
        reloadAppScopeList()
    }

    @objc private func toggleWhitelistEntry(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if sender.state == .on {
            config.enabledDefaultApps.insert(id)
        } else {
            config.enabledDefaultApps.remove(id)
        }
        config.apps = config.effectiveApps
        scheduleAutoSave()
    }

    @objc private func removeCustomApp(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        config.customApps.removeAll { $0.id == id }
        config.apps = config.effectiveApps
        reloadAppScopeCustomList()
        scheduleAutoSave()
    }

    @objc private func addCustomAppManually() {
        let alert = NSAlert()
        alert.messageText = L10n.text("Add custom app", "添加自定义应用")
        alert.informativeText = L10n.text(
            "Enter the app's bundle ID (found in /Applications/Some.app/Contents/Info.plist as CFBundleIdentifier).",
            "请输入应用的 Bundle ID（在 /Applications/xxx.app/Contents/Info.plist 的 CFBundleIdentifier 字段）。"
        )
        alert.alertStyle = .informational

        let nameField = NSTextField(string: "")
        nameField.placeholderString = L10n.text("Display name (e.g. Trae)", "显示名（例如 Trae）")
        nameField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let bidField = NSTextField(string: "")
        bidField.placeholderString = L10n.text("Bundle ID (e.g. com.trae.app)", "Bundle ID（例如 com.trae.app）")
        bidField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let stack = NSStackView(views: [nameField, bidField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.text("Add", "添加"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let trimmedBid = bidField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBid.isEmpty else {
            showValidationError(L10n.text("Bundle ID cannot be empty.", "Bundle ID 不能为空。"))
            return
        }
        if duplicateBundleID(trimmedBid) {
            showValidationError(L10n.text("This app is already in the list.", "该应用已在列表中。"))
            return
        }
        let displayName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = CustomApp(
            id: "custom-\(UUID().uuidString)",
            bundleID: trimmedBid,
            displayName: displayName.isEmpty ? trimmedBid : displayName,
            note: nil)
        config.customApps.append(app)
        config.apps = config.effectiveApps
        reloadAppScopeCustomList()
        scheduleAutoSave()
    }

    @objc private func addCustomAppFromFrontmost() {
        let bid = Frontmost.bundleID()
        guard !bid.isEmpty else {
            showValidationError(L10n.text("Could not read the foreground app's bundle ID.", "无法读取前台应用的 Bundle ID。"))
            return
        }
        if duplicateBundleID(bid) {
            showValidationError(L10n.text("This app is already in the list.", "该应用已在列表中。"))
            return
        }
        let displayName = frontmostAppDisplayName() ?? bid
        let app = CustomApp(id: "custom-\(UUID().uuidString)",
                            bundleID: bid,
                            displayName: displayName,
                            note: L10n.text("Added from current foreground app", "从当前前台应用添加"))
        config.customApps.append(app)
        config.apps = config.effectiveApps
        reloadAppScopeCustomList()
        scheduleAutoSave()
    }

    private func duplicateBundleID(_ bid: String) -> Bool {
        if WhitelistCatalog.defaultBundleIDs.contains(bid) { return true }
        return config.customApps.contains { $0.bundleID.caseInsensitiveCompare(bid) == .orderedSame }
    }

    private func frontmostAppDisplayName() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication {
            return app.localizedName
        }
        return nil
    }

    @objc private func modeControlChanged() {
        let newMode: AppMode
        switch modeControlInScope.selectedSegment {
        case 0: newMode = .whitelist
        case 1: newMode = .global
        case 2: newMode = .off
        default: return
        }
        if newMode == .global, config.mode != .global {
            if !confirmGlobalMode() {
                // Sync the on-screen control back to the actual config.
                syncModeControls()
                return
            }
        }
        config.mode = newMode
        // Mirror to the General page's segmented control so both stay in sync.
        syncModeControls()
        scheduleAutoSave()
    }

    private func syncModeControls() {
        let seg: Int
        switch config.mode {
        case .whitelist: seg = 0
        case .global: seg = 1
        case .off: seg = 2
        }
        if modeControl.selectedSegment != seg {
            modeControl.selectedSegment = seg
        }
        if modeControlInScope.selectedSegment != seg {
            modeControlInScope.selectedSegment = seg
        }
    }

    private func confirmGlobalMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.text(
            "Trigger in every app?",
            "在所有应用里触发？"
        )
        alert.informativeText = L10n.text(
            "Yes Engineer will send Return (and any configured text) to whatever app is in the foreground. This can submit half-typed messages, send chat replies, or trigger destructive actions in any app. Use Whitelist if you only want AI coding apps to respond.",
            "启用后，Yes 工程师会在任何前台应用里发送回车（以及配置的输入内容）。这可能提交未写完的消息、发出聊天回复，或在任意应用里触发不可撤销的操作。如果只想让 AI 编程应用响应，请改用“白名单”模式。"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("Enable All apps", "启用所有应用"))
        alert.addButton(withTitle: L10n.text("Cancel", "取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func section(title: String, rows: [NSView]) -> NSView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .left
        outer.spacing = 8
        outer.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        let stack = verticalStack([], spacing: 0)

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = makeInsetSeparator()
                separator.widthAnchor.constraint(equalToConstant: Layout.contentWidth - 32).isActive = true
                stack.addArrangedSubview(separator)
            }
            stack.addArrangedSubview(row)
        }

        let group = NSBox()
        group.boxType = .custom
        group.borderWidth = 1
        group.cornerRadius = 10
        group.borderColor = .separatorColor
        group.fillColor = .controlBackgroundColor
        group.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = group.contentView {
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            ])
        }

        outer.addArrangedSubview(titleLabel)
        outer.addArrangedSubview(group)
        return outer
    }

    private func formRow(_ title: String, _ content: NSView, help: String? = nil) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
        row.addArrangedSubview(label)

        let contentStack = verticalStack([content], spacing: 4)
        if let help = help {
            contentStack.addArrangedSubview(helpLabel(help))
        }
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(contentStack)
        row.widthAnchor.constraint(equalToConstant: Layout.contentWidth - 32).isActive = true
        return row
    }

    private func fullWidthRow(_ content: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .width
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        row.addArrangedSubview(content)
        row.widthAnchor.constraint(equalToConstant: Layout.contentWidth - 32).isActive = true
        return row
    }

    private func horizontalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .left
        stack.spacing = spacing
        return stack
    }

    private func helpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func suffixLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeInsetSeparator() -> NSBox {
        let separator = makeSeparator()
        separator.alphaValue = 0.65
        return separator
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func styleSwitch(_ button: NSButton) {
        button.setButtonType(.switch)
        button.controlSize = .regular
    }

    private func styleTextField(_ field: NSTextField, width: CGFloat, alignment: NSTextAlignment = .left) {
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = alignment
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func loadConfigIntoControls() {
        isLoadingControls = true
        defer { isLoadingControls = false }
        sensitivitySlider.doubleValue = config.minAmplitude
        updateSensitivityLabel()
        cooldownField.integerValue = config.cooldownMs
        cooldownStepper.integerValue = config.cooldownMs
        pauseAllSwitch.state = config.paused ? .on : .off
        pauseSlapSwitch.state = config.pauseSlapActions ? .on : .off
        pauseHotkeysSwitch.state = config.pauseHotkeys ? .on : .off
        syncModeControls()
        feedbackControl.selectedSegment = FeedbackMode.allCases.firstIndex(of: config.feedbackMode) ?? 0
        autoRequestAXSwitch.state = config.autoRequestAccessibility ? .on : .off
        reloadActionControls()
        refreshStatus()
    }

    private func reloadActionControls() {
        stopHotkeyRecording()
        slapActionPopup.removeAllItems()
        for action in config.textActions {
            slapActionPopup.addItem(withTitle: action.menuTitle)
            slapActionPopup.lastItem?.representedObject = action.id
        }
        if let idx = config.textActions.firstIndex(where: { $0.id == config.slapActionID }) {
            slapActionPopup.selectItem(at: idx)
        } else {
            slapActionPopup.selectItem(at: 0)
        }

        actionRowsStack.arrangedSubviews.forEach {
            actionRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        actionRows.removeAll()
        actionRowsStack.addArrangedSubview(makeActionHeaderRow())
        actionRowsStack.addArrangedSubview(makeInsetSeparator())
        for (index, action) in config.textActions.enumerated() {
            let row = SettingsActionRowView(action: action)
            row.onSelectionChanged = { [weak self] selectedRow in
                self?.selectActionRow(selectedRow)
            }
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
            actionRows.append(row)
            actionRowsStack.addArrangedSubview(row)
            if index < config.textActions.count - 1 {
                actionRowsStack.addArrangedSubview(makeInsetSeparator())
            }
        }
        if actionRows.first(where: { $0.actionID == config.slapActionID }) == nil {
            actionRows.first?.isSelected = true
        } else {
            actionRows.first(where: { $0.actionID == config.slapActionID })?.isSelected = true
        }
        updateDeleteActionButton()
    }

    private func makeActionHeaderRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        let columns: [(String, Int)] = [
            ("", 28),
            (L10n.text("Enabled", "启用"), 52),
            (L10n.text("Name", "名称"), 140),
            (L10n.text("Input", "输入内容"), 110),
            (L10n.text("Return", "回车"), 54),
            (L10n.text("Shortcut", "快捷键"), 170),
        ]
        for (title, width) in columns {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            if width == 110 {
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(width)).isActive = true
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            } else {
                label.widthAnchor.constraint(equalToConstant: CGFloat(width)).isActive = true
            }
            row.addArrangedSubview(label)
        }
        return row
    }

    private func readConfigFromControls(showValidationErrors: Bool = true) -> AppConfig? {
        var next = config
        next.minAmplitude = min(max(sensitivitySlider.doubleValue, SensitivitySliderView.minValue), SensitivitySliderView.maxValue)
        guard let cooldown = Int(cooldownField.stringValue), (100...5000).contains(cooldown) else {
            reportValidationError(L10n.text(
                "Cooldown must be a whole number between 100 and 5000 milliseconds.",
                "冷却时间必须是 100 到 5000 之间的整数毫秒值。"
            ), showAlert: showValidationErrors)
            return nil
        }
        next.cooldownMs = cooldown
        next.paused = pauseAllSwitch.state == .on
        next.pauseSlapActions = pauseSlapSwitch.state == .on
        next.pauseHotkeys = pauseHotkeysSwitch.state == .on
        next.mode = {
            switch modeControl.selectedSegment {
            case 0: return .whitelist
            case 1: return .global
            case 2: return .off
            default: return .whitelist
            }
        }()
        next.feedbackMode = FeedbackMode.allCases[safe: feedbackControl.selectedSegment] ?? .toast
        next.autoRequestAccessibility = autoRequestAXSwitch.state == .on

        var nextActions: [TextAction] = []
        var seenHotkeys = Set<String>()
        for row in actionRows {
            guard var action = row.action() else {
                reportValidationError(L10n.text("One shortcut is invalid.", "有一个快捷键格式不正确。"),
                                      showAlert: showValidationErrors)
                return nil
            }
            if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reportValidationError(L10n.text("Action names cannot be empty.", "动作名称不能为空。"),
                                      showAlert: showValidationErrors)
                return nil
            }
            let signature = "\(action.hotkey.modifiers):\(action.hotkey.keyCode)"
            if action.enabled && seenHotkeys.contains(signature) {
                reportValidationError(L10n.format(
                    "The shortcut %@ is used more than once.",
                    "快捷键 %@ 被重复使用。",
                    action.hotkey.displayName
                ), showAlert: showValidationErrors)
                return nil
            }
            if action.enabled {
                seenHotkeys.insert(signature)
            }
            action.input = action.input.trimmingCharacters(in: .newlines)
            nextActions.append(action)
        }
        if nextActions.isEmpty {
            reportValidationError(L10n.text("Keep at least one action.", "至少需要保留一个动作。"),
                                  showAlert: showValidationErrors)
            return nil
        }
        next.textActions = nextActions

        if let selectedID = slapActionPopup.selectedItem?.representedObject as? String,
           nextActions.contains(where: { $0.id == selectedID }) {
            next.slapActionID = selectedID
        } else if let selectedID = selectedActionID(),
                  nextActions.contains(where: { $0.id == selectedID }) {
            next.slapActionID = selectedID
        } else {
            next.slapActionID = nextActions.first(where: { $0.id == TextAction.defaultSlapActionID })?.id
                ?? nextActions[0].id
        }

        return next
    }

    private func updateSensitivityLabel() {
        sensitivityValue.stringValue = String(format: "%.3f g", sensitivitySlider.doubleValue)
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Settings need attention", "设置需要处理")
        alert.informativeText = message
        alert.runModal()
    }

    private func reportValidationError(_ message: String, showAlert: Bool) {
        if showAlert {
            showValidationError(message)
        }
    }

    private func scheduleAutoSave(delay: TimeInterval = 0.2) {
        guard !isLoadingControls else { return }
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.commitChanges()
        }
    }

    @discardableResult
    private func commitChanges(showValidationErrors: Bool = false) -> Bool {
        guard let next = readConfigFromControls(showValidationErrors: showValidationErrors) else { return false }
        config = next
        onChange?(next)
        return true
    }

    private func hotkeyConflictMessage(_ candidate: HotkeySpec,
                                       excluding sourceRow: SettingsActionRowView) -> String? {
        let duplicate = actionRows.contains { row in
            row !== sourceRow && row.isEnabled && row.hotkey == candidate
        }
        if duplicate {
            return L10n.format("The shortcut %@ is already assigned to another action.",
                               "快捷键 %@ 已分配给其他动作。",
                               candidate.displayName)
        }
        return HotkeyConflictDetector.systemConflictMessage(for: candidate)
    }

    @objc private func sensitivityChanged() {
        updateSensitivityLabel()
        scheduleAutoSave()
    }

    @objc private func pageChanged() {
        updateVisiblePage()
    }

    private func updateVisiblePage() {
        let selected = max(0, pageControl.selectedSegment)
        for (index, page) in pageViews.enumerated() {
            page.isHidden = index != selected
        }
    }

    @objc private func cooldownStepperChanged() {
        cooldownField.integerValue = cooldownStepper.integerValue
        scheduleAutoSave()
    }

    @objc private func slapActionChanged() {
        guard let id = slapActionPopup.selectedItem?.representedObject as? String,
              let row = actionRows.first(where: { $0.actionID == id }) else { return }
        selectActionRow(row)
        scheduleAutoSave()
    }

    @objc private func controlChanged() {
        scheduleAutoSave()
    }

    @objc private func addAction() {
        guard let snapshot = snapshotActionsForEditing() else { return }
        let nextNumber = snapshot.count + 1
        let newAction = TextAction(id: nextActionID(existing: snapshot),
                                   title: L10n.format("Custom Action %d", "自定义动作 %d", nextNumber),
                                   input: "",
                                   autoPressReturn: true,
                                   hotkey: nextAvailableHotkey(existing: snapshot),
                                   enabled: true)
        config.textActions = snapshot + [newAction]
        config.slapActionID = newAction.id
        reloadActionControls()
        scheduleAutoSave(delay: 0)
    }

    @objc private func deleteSelectedAction() {
        guard actionRows.count > 1, let selectedID = selectedActionID() else { return }
        guard let snapshot = snapshotActionsForEditing() else { return }
        config.textActions = snapshot.filter { $0.id != selectedID }
        if !config.textActions.contains(where: { $0.id == config.slapActionID }) {
            config.slapActionID = config.textActions.first(where: { $0.id == TextAction.defaultSlapActionID })?.id
                ?? config.textActions.first?.id
                ?? TextAction.defaultSlapActionID
        }
        reloadActionControls()
        scheduleAutoSave(delay: 0)
    }

    @objc private func restoreDefaultActions() {
        config.textActions = TextAction.defaults
        config.slapActionID = TextAction.defaultSlapActionID
        reloadActionControls()
        scheduleAutoSave(delay: 0)
    }

    @objc private func restoreDefaults() {
        config = AppConfig()
        loadConfigIntoControls()
        scheduleAutoSave(delay: 0)
    }

    @objc private func closePanel() {
        stopHotkeyRecording()
        close()
    }

    @objc private func revealConfigFile() {
        if FileManager.default.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.open(configURL.deletingLastPathComponent())
        }
    }

    private func stopHotkeyRecording() {
        actionRows.forEach { $0.stopHotkeyRecording() }
    }

    @objc private func reinstallDaemon() {
        onReinstallDaemon?()
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
    }

    private func selectedActionID() -> String? {
        actionRows.first(where: { $0.isSelected })?.actionID
    }

    private func selectActionRow(_ selectedRow: SettingsActionRowView) {
        for row in actionRows {
            row.isSelected = row === selectedRow
        }
        if let index = config.textActions.firstIndex(where: { $0.id == selectedRow.actionID }) {
            slapActionPopup.selectItem(at: index)
            config.slapActionID = selectedRow.actionID
        }
        updateDeleteActionButton()
        scheduleAutoSave()
    }

    private func updateDeleteActionButton() {
        deleteActionButton.isEnabled = actionRows.count > 1 && selectedActionID() != nil
    }

    private func snapshotActionsForEditing() -> [TextAction]? {
        var result: [TextAction] = []
        for row in actionRows {
            guard let action = row.action() else {
                showValidationError(L10n.text("One shortcut is invalid.", "有一个快捷键格式不正确。"))
                return nil
            }
            result.append(action)
        }
        return result
    }

    private func nextActionID(existing actions: [TextAction]) -> String {
        let ids = Set(actions.map(\.id))
        var index = actions.count + 1
        while ids.contains("custom-\(index)") {
            index += 1
        }
        return "custom-\(index)"
    }

    private func nextAvailableHotkey(existing actions: [TextAction]) -> HotkeySpec {
        let used = Set(actions.map { "\($0.hotkey.modifiers):\($0.hotkey.keyCode)" })
        for key in ["n", "b", "v", "x", "z", "a", "s", "d", "f", "g", "h", "j", "k", "l", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            guard let candidate = HotkeySpec.parse("option+shift+\(key)") else { continue }
            let signature = "\(candidate.modifiers):\(candidate.keyCode)"
            if !used.contains(signature) {
                return candidate
            }
        }
        return HotkeySpec(keyCode: 0x31, modifiers: HotkeyModifier.control | HotkeyModifier.option | HotkeyModifier.shift)
    }
}

private final class SettingsActionRowView: NSStackView {
    private let selectionButton: NSButton
    private let sourceID: String
    private let enabledSwitch: NSButton
    private let titleField: NSTextField
    private let inputField: NSTextField
    private let returnSwitch: NSButton
    private let hotkeyRecorder: HotkeyRecorderView
    var onSelectionChanged: ((SettingsActionRowView) -> Void)?
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

    var actionID: String {
        sourceID
    }

    var isEnabled: Bool {
        enabledSwitch.state == .on
    }

    var hotkey: HotkeySpec {
        hotkeyRecorder.currentHotkey()
    }

    var isSelected: Bool {
        get { selectionButton.state == .on }
        set {
            selectionButton.state = newValue ? .on : .off
        }
    }

    init(action: TextAction) {
        self.sourceID = action.id
        self.selectionButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
        self.enabledSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.titleField = NSTextField(string: action.title)
        self.inputField = NSTextField(string: action.input)
        self.returnSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.hotkeyRecorder = HotkeyRecorderView(hotkey: action.hotkey, width: 170)
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        selectionButton.target = self
        selectionButton.action = #selector(selectRow)
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)
        returnSwitch.target = self
        returnSwitch.action = #selector(valueChanged)
        enabledSwitch.setButtonType(.switch)
        returnSwitch.setButtonType(.switch)
        enabledSwitch.state = action.enabled ? .on : .off
        returnSwitch.state = action.autoPressReturn ? .on : .off
        titleField.font = .systemFont(ofSize: 13)
        inputField.font = .systemFont(ofSize: 13)
        titleField.delegate = self
        inputField.delegate = self
        hotkeyRecorder.onHotkeyChanged = { [weak self] _ in
            self?.onChange?()
        }

        selectionButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        enabledSwitch.widthAnchor.constraint(equalToConstant: 52).isActive = true
        titleField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        inputField.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        returnSwitch.widthAnchor.constraint(equalToConstant: 54).isActive = true

        addArrangedSubview(selectionButton)
        addArrangedSubview(enabledSwitch)
        addArrangedSubview(titleField)
        addArrangedSubview(inputField)
        addArrangedSubview(returnSwitch)
        addArrangedSubview(hotkeyRecorder)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action() -> TextAction? {
        return TextAction(id: sourceID,
                          title: titleField.stringValue,
                          input: inputField.stringValue,
                          autoPressReturn: returnSwitch.state == .on,
                          hotkey: hotkeyRecorder.currentHotkey(),
                          enabled: enabledSwitch.state == .on)
    }

    func stopHotkeyRecording() {
        hotkeyRecorder.stopRecording()
    }

    @objc private func selectRow() {
        onSelectionChanged?(self)
    }

    @objc private func valueChanged() {
        onChange?()
    }

    @objc private func enabledChanged() {
        if onValidationRequested?() == false {
            enabledSwitch.state = enabledSwitch.state == .on ? .off : .on
        }
    }
}

extension SettingsActionRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onChange?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        _ = onValidationRequested?()
    }
}

extension SettingsWindowController: NSWindowDelegate, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        scheduleAutoSave()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitChanges(showValidationErrors: true)
    }

    func windowWillClose(_ notification: Notification) {
        autoSaveTimer?.invalidate()
        commitChanges(showValidationErrors: true)
        stopHotkeyRecording()
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return []
        }
        return urls.contains(where: { $0.pathExtension.lowercased() == "app" }) ? .copy : []
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        var added = 0
        for url in urls where url.pathExtension.lowercased() == "app" {
            if let app = makeCustomAppFromAppURL(url) {
                if duplicateBundleID(app.bundleID) { continue }
                config.customApps.append(app)
                added += 1
            }
        }
        if added > 0 {
            config.apps = config.effectiveApps
            reloadAppScopeCustomList()
            scheduleAutoSave()
            return true
        }
        return false
    }

    private func makeCustomAppFromAppURL(_ url: URL) -> CustomApp? {
        guard let bid = Bundle(url: url)?.bundleIdentifier else { return nil }
        let displayName = (url.deletingPathExtension().lastPathComponent)
        return CustomApp(id: "custom-\(UUID().uuidString)",
                         bundleID: bid,
                         displayName: displayName,
                         note: L10n.text("Added by dragging the app", "通过拖拽应用添加"))
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ClickableContainer: NSView {
    var representedCategory: WhitelistEntry.Category?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
