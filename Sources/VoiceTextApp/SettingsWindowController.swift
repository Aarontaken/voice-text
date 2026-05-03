import AppKit
import VoiceTextCore

final class SettingsWindowController: NSWindowController {
    private static let defaultHotkeyKeyCode: UInt32 = 9
    private static let defaultHotkeyModifiers: UInt32 = (1 << 12) | (1 << 11)
    private static let rowLabelWidth: CGFloat = 84
    private static let rowControlMinWidth: CGFloat = 340

    private let settingsStore: SettingsStore
    private let onSave: (ASRConfiguration) -> Void

    private let environmentPopup = NSPopUpButton()
    private let phoneField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let accountStatusLabel = NSTextField(labelWithString: "")
    private let advancedStatusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "登录并保存", target: nil, action: nil)
    private let silenceStopField = NSTextField()
    private let resetAdvancedButton = NSButton(title: "恢复默认", target: nil, action: nil)
    private let saveAdvancedButton = NSButton(title: "保存高级设置", target: nil, action: nil)
    private var hotkeyKeyCode = SettingsWindowController.defaultHotkeyKeyCode
    private var hotkeyModifiers = SettingsWindowController.defaultHotkeyModifiers

    private struct AdvancedASRSettings {
        let silence4StopInMilli: Int
    }

    private enum SettingsValidationError: LocalizedError {
        case invalidMilliseconds(label: String)

        var errorDescription: String? {
            switch self {
            case let .invalidMilliseconds(label):
                return "\(label) 必须填写合理的毫秒数"
            }
        }
    }

    init(settingsStore: SettingsStore, onSave: @escaping (ASRConfiguration) -> Void) {
        self.settingsStore = settingsStore
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceText 设置"
        super.init(window: window)
        buildContent()
        loadValues()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        environmentPopup.addItems(withTitles: ASRConfiguration.Environment.allCases.map(\.rawValue))
        phoneField.placeholderString = "请输入老师账号手机号"
        passwordField.placeholderString = "请输入密码"
        silenceStopField.placeholderString = "默认 500，最小 200，单位毫秒"

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "VoiceText 设置")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "登录后使用 Control 录音，可按住说话，也可双击开始或停止。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(20, after: subtitle)
        configureStatusLabel(accountStatusLabel)
        configureStatusLabel(advancedStatusLabel)

        stack.addArrangedSubview(section(
            title: "账号登录",
            views: [
                row(label: "环境", control: environmentPopup),
                row(label: "手机号", control: phoneField),
                row(label: "密码", control: passwordField),
                statusRow(accountStatusLabel),
                actionRow(button: saveButton)
            ]
        ))
        stack.addArrangedSubview(section(
            title: "快捷键",
            views: [
                hotkeyRow()
            ]
        ))
        stack.addArrangedSubview(section(
            title: "高级",
            views: [
                advancedSettingRow(
                    label: "完成停顿",
                    control: silenceStopField,
                    help: "你说完一句话后，停顿多久返回分段结果。默认 500ms，越小返回越快，也更容易提前切断。"
                ),
                actionButtonsRow(buttons: [resetAdvancedButton, saveAdvancedButton]),
                statusRow(advancedStatusLabel)
            ]
        ))

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        resetAdvancedButton.target = self
        resetAdvancedButton.action = #selector(resetAdvancedSettings)
        resetAdvancedButton.bezelStyle = .rounded
        saveAdvancedButton.target = self
        saveAdvancedButton.action = #selector(saveAdvancedSettings)
        saveAdvancedButton.bezelStyle = .rounded

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentView.addSubview(scrollView)
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
        DispatchQueue.main.async { [weak scrollView, weak documentView] in
            guard let scrollView, let documentView else { return }
            documentView.layoutSubtreeIfNeeded()
            scrollView.layoutSubtreeIfNeeded()
            let topY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: topY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func section(title: String, views: [NSView]) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.18).cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel] + views)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func configureStatusLabel(_ label: NSTextField) {
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.font = .systemFont(ofSize: 12)
    }

    private func statusRow(_ label: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .top

        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: Self.rowLabelWidth).isActive = true

        label.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowControlMinWidth).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(label)
        return stack
    }

    private func hintRow(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.textColor = .tertiaryLabelColor
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return statusRow(label)
    }

    private func advancedSettingRow(label: String, control: NSView, help: String) -> NSView {
        let container = NSView()

        let labelView = NSTextField(labelWithString: label)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.textColor = .secondaryLabelColor

        let detailLabel = NSTextField(labelWithString: help)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0

        let detailStack = NSStackView(views: [control, detailLabel])
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.orientation = .vertical
        detailStack.spacing = 4
        detailStack.alignment = .leading

        container.addSubview(labelView)
        container.addSubview(detailStack)
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            labelView.widthAnchor.constraint(equalToConstant: Self.rowLabelWidth),
            detailStack.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 14),
            detailStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            detailStack.topAnchor.constraint(equalTo: container.topAnchor),
            detailStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            detailStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowControlMinWidth),
            detailLabel.widthAnchor.constraint(equalTo: detailStack.widthAnchor)
        ])
        return container
    }

    private func row(label: String, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY

        let labelView = NSTextField(labelWithString: label)
        labelView.textColor = .secondaryLabelColor
        labelView.widthAnchor.constraint(equalToConstant: Self.rowLabelWidth).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowControlMinWidth).isActive = true

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(control)
        return stack
    }

    private func checkboxRow(control: NSButton) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY

        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: Self.rowLabelWidth).isActive = true

        control.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowControlMinWidth).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(control)
        return stack
    }

    private func actionRow(button: NSButton) -> NSView {
        actionButtonsRow(buttons: [button])
    }

    private func actionButtonsRow(buttons: [NSButton]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    private func hotkeyRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY

        let labelView = NSTextField(labelWithString: "录音方式")
        labelView.textColor = .secondaryLabelColor
        labelView.widthAnchor.constraint(equalToConstant: Self.rowLabelWidth).isActive = true

        hotkeyValueLabel.font = .systemFont(ofSize: 13)
        hotkeyValueLabel.textColor = .labelColor
        hotkeyValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.rowControlMinWidth).isActive = true
        hotkeyValueLabel.lineBreakMode = .byWordWrapping
        hotkeyValueLabel.maximumNumberOfLines = 0

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(hotkeyValueLabel)
        return stack
    }

    private func loadValues() {
        let config = (try? settingsStore.load()) ?? ASRConfiguration.defaultConfiguration()
        environmentPopup.selectItem(withTitle: config.environment.rawValue)
        phoneField.stringValue = config.phoneNumber
        passwordField.stringValue = config.password
        hotkeyKeyCode = config.hotkeyKeyCode
        hotkeyModifiers = config.hotkeyModifiers
        applyAdvancedSettings(from: config)
        updateHotkeyLabel()
        accountStatusLabel.stringValue = config.authToken.isEmpty ? "未登录" : "已保存登录 token"
        advancedStatusLabel.stringValue = "建议保持默认；调大静音毫秒数会让识别等待更久。"
    }

    @objc private func save() {
        saveButton.isEnabled = false
        accountStatusLabel.stringValue = "正在登录..."

        Task { [weak self] in
            await self?.loginAndSave()
        }
    }

    @MainActor
    private func loginAndSave() async {
        let previousConfig = (try? settingsStore.load()) ?? ASRConfiguration.defaultConfiguration()
        let environment = ASRConfiguration.Environment(rawValue: environmentPopup.titleOfSelectedItem ?? "") ?? .test
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let advanced: AdvancedASRSettings
        do {
            advanced = try readAdvancedSettings()
        } catch {
            accountStatusLabel.stringValue = error.localizedDescription
            saveButton.isEnabled = true
            NSAlert(error: error).runModal()
            return
        }
        let baseConfig = ASRConfiguration(
            environment: environment,
            userId: previousConfig.userId,
            role: .teacher,
            deviceId: previousConfig.deviceId,
            cookieHeader: previousConfig.cookieHeader,
            phoneNumber: phone,
            password: password,
            authToken: previousConfig.authToken,
            additionalHeaders: previousConfig.additionalHeaders,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            useAutoVAD: true,
            silence4StopInMilli: advanced.silence4StopInMilli,
            silence4TimeoutInMilli: 500,
            needNormalization: false,
            needDenoise: true
        )

        do {
            let token = try await PasswordLoginClient.login(
                environment: environment,
                phone: phone,
                password: password
            )
            let loggedInConfig = PasswordLoginClient.configurationByApplyingLogin(
                token: token,
                phone: phone,
                password: password,
                to: baseConfig
            )
            let refreshedConfig = (try? await AuthCookieClient.refreshCookies(for: loggedInConfig)) ?? loggedInConfig
            try settingsStore.save(refreshedConfig)
            onSave(refreshedConfig)
            window?.close()
        } catch {
            accountStatusLabel.stringValue = error.localizedDescription
            saveButton.isEnabled = true
            NSAlert(error: error).runModal()
        }
    }

    @objc private func resetAdvancedSettings() {
        applyAdvancedSettings(from: ASRConfiguration.defaultConfiguration())
        advancedStatusLabel.stringValue = "已恢复默认值，点击“保存高级设置”后生效"
    }

    @objc private func saveAdvancedSettings() {
        do {
            let previousConfig = (try? settingsStore.load()) ?? ASRConfiguration.defaultConfiguration()
            let advanced = try readAdvancedSettings()
            let updated = configurationByReplacingAdvancedSettings(in: previousConfig, with: advanced)
            try settingsStore.save(updated)
            onSave(updated)
            advancedStatusLabel.stringValue = "高级设置已保存，下次识别生效"
        } catch {
            advancedStatusLabel.stringValue = error.localizedDescription
            NSAlert(error: error).runModal()
        }
    }

    private func applyAdvancedSettings(from config: ASRConfiguration) {
        silenceStopField.stringValue = String(config.silence4StopInMilli)
    }

    private func readAdvancedSettings() throws -> AdvancedASRSettings {
        AdvancedASRSettings(
            silence4StopInMilli: try parseMilliseconds(silenceStopField, label: "完成停顿", range: 200...10_000)
        )
    }

    private func parseMilliseconds(_ field: NSTextField, label: String, range: ClosedRange<Int>) throws -> Int {
        let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, range.contains(value) else {
            throw SettingsValidationError.invalidMilliseconds(label: label)
        }
        return value
    }

    private func configurationByReplacingAdvancedSettings(
        in configuration: ASRConfiguration,
        with advanced: AdvancedASRSettings
    ) -> ASRConfiguration {
        ASRConfiguration(
            environment: configuration.environment,
            userId: configuration.userId,
            role: configuration.role,
            deviceId: configuration.deviceId,
            cookieHeader: configuration.cookieHeader,
            phoneNumber: configuration.phoneNumber,
            password: configuration.password,
            authToken: configuration.authToken,
            additionalHeaders: configuration.additionalHeaders,
            hotkeyKeyCode: configuration.hotkeyKeyCode,
            hotkeyModifiers: configuration.hotkeyModifiers,
            useAutoVAD: true,
            silence4StopInMilli: advanced.silence4StopInMilli,
            silence4TimeoutInMilli: 500,
            needNormalization: false,
            needDenoise: true
        )
    }

    private func updateHotkeyLabel() {
        hotkeyValueLabel.stringValue = hotkeyDescription(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private func hotkeyDescription(keyCode: UInt32, modifiers: UInt32) -> String {
        "按住 Control 说话，松开结束\n双击 Control 开始/停止"
    }
}
