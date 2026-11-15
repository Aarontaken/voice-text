import AppKit
import ApplicationServices
import VoiceTextCore

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let onSave: (ASRConfiguration) -> Void

    private let modeControl = NSSegmentedControl(
        labels: ["一句话识别", "实时识别"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let modeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let apiKeyField = NSSecureTextField()
    private let resourcePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let endWindowSlider = NSSlider()
    private let endWindowValueLabel = NSTextField(labelWithString: "800 ms")
    private let itnSwitch = NSSwitch()
    private let puncSwitch = NSSwitch()
    private let ddcSwitch = NSSwitch()
    private let statusLabel = NSTextField(labelWithString: "")
    private let accessibilityDot = NSView()
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "去开启", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let resetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    private var didBecomeActiveObserver: NSObjectProtocol?

    private enum SettingsValidationError: LocalizedError, Equatable {
        case missingAPIKey
        case invalidEndWindow

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "请填写豆包 API Key"
            case .invalidEndWindow:
                return "完成停顿需要设置在 300–5000ms 之间"
            }
        }
    }

    init(settingsStore: SettingsStore, onSave: @escaping (ASRConfiguration) -> Void) {
        self.settingsStore = settingsStore
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceText 设置"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)

        buildContent()
        loadValues()
        observeActivation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    // MARK: - UI

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        modeControl.segmentStyle = .rounded
        modeControl.segmentDistribution = .fillEqually
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.heightAnchor.constraint(equalToConstant: 26).isActive = true

        modeDescriptionLabel.font = .systemFont(ofSize: 11)
        modeDescriptionLabel.textColor = .tertiaryLabelColor
        modeDescriptionLabel.maximumNumberOfLines = 0

        apiKeyField.placeholderString = "粘贴火山引擎控制台创建的 API Key"
        apiKeyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.controlSize = .regular
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        resourcePopup.addItems(withTitles: ASRConfiguration.Resource.allCases.map(\.displayName))
        languagePopup.addItems(withTitles: ASRConfiguration.languageOptions.map(\.title))

        endWindowSlider.minValue = 300
        endWindowSlider.maxValue = 5_000
        endWindowSlider.doubleValue = 800
        endWindowSlider.isContinuous = true
        endWindowSlider.target = self
        endWindowSlider.action = #selector(endWindowChanged)
        endWindowSlider.controlSize = .regular

        endWindowValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        endWindowValueLabel.textColor = .secondaryLabelColor
        endWindowValueLabel.alignment = .right

        for toggle in [itnSwitch, puncSwitch, ddcSwitch] {
            toggle.controlSize = .small
        }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1

        accessibilityDot.wantsLayer = true
        accessibilityDot.layer?.cornerRadius = 4
        accessibilityDot.translatesAutoresizingMaskIntoConstraints = false
        accessibilityDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        accessibilityDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        accessibilityLabel.font = .systemFont(ofSize: 11)
        accessibilityLabel.textColor = .secondaryLabelColor

        accessibilityButton.isBordered = false
        accessibilityButton.contentTintColor = .linkColor
        accessibilityButton.font = .systemFont(ofSize: 11)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)

        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)

        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetToDefaults)

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        let recognitionCard = makeCard(
            title: "语音识别",
            symbol: "waveform",
            rows: [
                makeModeRow(),
                makeAPIKeyRow(),
                makeModelLanguageRow()
            ]
        )
        let effectsCard = makeCard(
            title: "识别效果",
            symbol: "slider.horizontal.3",
            rows: [
                makeEndWindowRow(),
                makeTogglesRow()
            ]
        )
        let shortcutsCard = makeShortcutsCard()
        let accessibilityRow = makeAccessibilityRow()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 2).isActive = true
        let divider = NSBox()
        divider.boxType = .separator
        let footer = makeFooter()

        root.addArrangedSubview(header)
        root.setCustomSpacing(18, after: header)
        root.addArrangedSubview(recognitionCard)
        root.addArrangedSubview(effectsCard)
        root.addArrangedSubview(shortcutsCard)
        root.addArrangedSubview(accessibilityRow)
        root.addArrangedSubview(spacer)
        root.addArrangedSubview(divider)
        root.addArrangedSubview(footer)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        for view in [header, recognitionCard, effectsCard, shortcutsCard, accessibilityRow, divider, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    private func makeHeader() -> NSView {
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let title = NSTextField(labelWithString: "VoiceText")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "按住 ⌥ 说话，松开自动落字")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionLabel = NSTextField(labelWithString: version.isEmpty ? "" : "v\(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .right

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [iconView, textStack, spacer, versionLabel])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        return header
    }

    private func makeModeRow() -> NSView {
        let stack = NSStackView(views: [modeControl, modeDescriptionLabel])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        modeControl.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        modeDescriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updateModeDescription()
        return stack
    }

    private func makeAPIKeyRow() -> NSView {
        let label = fieldLabel("API Key")

        let link = NSButton(title: "获取", target: self, action: #selector(openAPIKeyPage))
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.font = .systemFont(ofSize: 12)
        link.setContentHuggingPriority(.required, for: .horizontal)
        link.toolTip = "打开火山引擎 API Key 管理页面"

        let row = NSStackView(views: [label, apiKeyField, link])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func makeModelLanguageRow() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let model = labeledPopup(title: "模型版本", popup: resourcePopup)
        let language = labeledPopup(title: "识别语种", popup: languagePopup)
        let pair = NSStackView(views: [model, language])
        pair.orientation = .horizontal
        pair.spacing = 16
        pair.distribution = .fillEqually

        let row = NSStackView(views: [spacer, pair])
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .top
        pair.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -94).isActive = true
        return row
    }

    private func makeEndWindowRow() -> NSView {
        let title = NSTextField(labelWithString: "完成停顿")
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        endWindowValueLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let titleRow = NSStackView(views: [title, spacer, endWindowValueLabel])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .centerY

        let help = NSTextField(wrappingLabelWithString: "静音超过这个时长就认为一句话结束。调小分句更快，调大更稳。")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.maximumNumberOfLines = 0

        let stack = NSStackView(views: [titleRow, endWindowSlider, help])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        endWindowSlider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeTogglesRow() -> NSView {
        let itn = toggleItem(title: "数字/日期规范化", tooltip: "把口语数字、日期转成书面格式", toggle: itnSwitch)
        let punc = toggleItem(title: "自动标点", tooltip: "自动补充逗号、句号等标点", toggle: puncSwitch)
        let ddc = toggleItem(title: "语义顺滑", tooltip: "去掉语气词、重复词，让句子更连贯", toggle: ddcSwitch)

        let row = NSStackView(views: [itn, punc, ddc])
        row.orientation = .horizontal
        row.spacing = 18
        row.distribution = .fillEqually
        row.alignment = .centerY
        return row
    }

    private func makeShortcutsCard() -> NSView {
        let hold = shortcutItem(keys: ["⌥"], text: "按住 0.25 秒说话，松开结束")
        let locked = shortcutItem(keys: ["⌃", "⌃"], text: "双击开始 / 停止连续录音")

        let row = NSStackView(views: [hold, locked])
        row.orientation = .horizontal
        row.spacing = 28
        row.alignment = .centerY
        return makeCard(title: "快捷键", symbol: "keyboard", rows: [row])
    }

    private func shortcutItem(keys: [String], text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor

        var views: [NSView] = keys.map(keyCap)
        views.append(label)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        return stack
    }

    private func keyCap(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        label.layer?.borderWidth = 1
        label.layer?.borderColor = NSColor.separatorColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true
        label.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return label
    }

    private func makeAccessibilityRow() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [accessibilityDot, accessibilityLabel, spacer, accessibilityButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func makeFooter() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [statusLabel, spacer, resetButton, saveButton])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func makeCard(title: String, symbol: String, rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 12
        box.contentViewMargins = NSSize(width: 16, height: 14)
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [icon, titleLabel])
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY

        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = box.contentView else { return box }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return box
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 84).isActive = true
        return label
    }

    private func labeledPopup(title: String, popup: NSPopUpButton) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [label, popup])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        popup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func toggleItem(title: String, tooltip: String, toggle: NSSwitch) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.toolTip = tooltip

        let stack = NSStackView(views: [toggle, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.toolTip = tooltip
        return stack
    }

    // MARK: - Values

    private func loadValues() {
        let config = (try? settingsStore.load()) ?? ASRConfiguration.defaultConfiguration()
        apply(config)
        statusLabel.stringValue = config.hasAPIKey ? "API Key 已配置" : "尚未配置 API Key"
        statusLabel.textColor = .tertiaryLabelColor
        refreshAccessibilityStatus()
    }

    private func apply(_ config: ASRConfiguration) {
        modeControl.selectedSegment = config.mode == .realtime ? 1 : 0
        updateModeDescription()

        apiKeyField.stringValue = config.apiKey

        if let index = ASRConfiguration.Resource.allCases.firstIndex(of: config.resource) {
            resourcePopup.selectItem(at: index)
        }
        let languageIndex = ASRConfiguration.languageOptions.firstIndex { $0.value == config.language } ?? 0
        languagePopup.selectItem(at: languageIndex)

        endWindowSlider.doubleValue = Double(config.endWindowSize)
        updateEndWindowLabel()

        itnSwitch.state = config.enableITN ? .on : .off
        puncSwitch.state = config.enablePunc ? .on : .off
        ddcSwitch.state = config.enableDDC ? .on : .off
    }

    private func readConfiguration() throws -> ASRConfiguration {
        let previous = (try? settingsStore.load()) ?? ASRConfiguration.defaultConfiguration()
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw SettingsValidationError.missingAPIKey
        }

        let mode: ASRConfiguration.Mode = modeControl.selectedSegment == 1 ? .realtime : .oneShot

        let resourceIndex = resourcePopup.indexOfSelectedItem
        let resource = ASRConfiguration.Resource.allCases.indices.contains(resourceIndex)
            ? ASRConfiguration.Resource.allCases[resourceIndex]
            : .seedASRDuration

        let languageIndex = languagePopup.indexOfSelectedItem
        let language = ASRConfiguration.languageOptions.indices.contains(languageIndex)
            ? ASRConfiguration.languageOptions[languageIndex].value
            : ""

        let endWindow = Int(endWindowSlider.doubleValue.rounded())
        guard (300...5_000).contains(endWindow) else {
            throw SettingsValidationError.invalidEndWindow
        }

        return ASRConfiguration(
            apiKey: apiKey,
            mode: mode,
            resource: resource,
            language: language,
            enableITN: itnSwitch.state == .on,
            enablePunc: puncSwitch.state == .on,
            enableDDC: ddcSwitch.state == .on,
            showUtterances: previous.showUtterances,
            endWindowSize: endWindow,
            forceToSpeechTime: previous.forceToSpeechTime
        )
    }

    private func updateModeDescription() {
        if modeControl.selectedSegment == 1 {
            modeDescriptionLabel.stringValue = "边说边返回分句，停顿约 0.8 秒后逐句插入；适合长段口述。"
        } else {
            modeDescriptionLabel.stringValue = "松开 Option 后返回整句，准确率更高；适合短句和一次性输入。"
        }
    }

    private func updateEndWindowLabel() {
        endWindowValueLabel.stringValue = "\(Int(endWindowSlider.doubleValue.rounded())) ms"
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        updateModeDescription()
    }

    @objc private func endWindowChanged() {
        updateEndWindowLabel()
    }

    @objc private func save() {
        do {
            let config = try readConfiguration()
            try settingsStore.save(config)
            onSave(config)
            window?.close()
        } catch let error as SettingsValidationError {
            showError(error.localizedDescription, focus: error == .missingAPIKey ? apiKeyField : nil)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func resetToDefaults() {
        var defaults = ASRConfiguration.defaultConfiguration()
        defaults.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(defaults)
        statusLabel.stringValue = "已恢复默认值，点击保存生效"
        statusLabel.textColor = .tertiaryLabelColor
    }

    @objc private func openAPIKeyPage() {
        guard let url = URL(string: "https://console.volcengine.com/speech/new/setting/apikeys") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showError(_ message: String, focus: NSView? = nil) {
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        NSSound.beep()
        if let focus {
            window?.makeFirstResponder(focus)
        }
    }

    private func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        accessibilityDot.layer?.backgroundColor = (trusted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        accessibilityLabel.stringValue = trusted ? "辅助功能已开启" : "辅助功能未开启，文字无法自动写入"
        accessibilityButton.isHidden = trusted
    }

    private func observeActivation() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAccessibilityStatus()
        }
    }
}
