import AppKit
import VoiceTextCore

final class SettingsWindowController: NSWindowController {
    private static let defaultHotkeyKeyCode: UInt32 = 9
    private static let defaultHotkeyModifiers: UInt32 = (1 << 12) | (1 << 11)

    private let settingsStore: SettingsStore
    private let onSave: (ASRConfiguration) -> Void

    private let environmentPopup = NSPopUpButton()
    private let phoneField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let hotkeyValueLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "登录并保存", target: nil, action: nil)
    private var hotkeyKeyCode = SettingsWindowController.defaultHotkeyKeyCode
    private var hotkeyModifiers = SettingsWindowController.defaultHotkeyModifiers

    init(settingsStore: SettingsStore, onSave: @escaping (ASRConfiguration) -> Void) {
        self.settingsStore = settingsStore
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable],
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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "VoiceText 设置")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "登录后按住 Control 说话，松开结束。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(20, after: subtitle)

        stack.addArrangedSubview(section(
            title: "账号登录",
            views: [
                row(label: "环境", control: environmentPopup),
                row(label: "手机号", control: phoneField),
                row(label: "密码", control: passwordField)
            ]
        ))
        stack.addArrangedSubview(section(
            title: "快捷键",
            views: [
                hotkeyRow()
            ]
        ))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        stack.addArrangedSubview(saveButton)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])
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

    private func row(label: String, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14

        let labelView = NSTextField(labelWithString: label)
        labelView.textColor = .secondaryLabelColor
        labelView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(control)
        return stack
    }

    private func hotkeyRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14

        let labelView = NSTextField(labelWithString: "录音方式")
        labelView.textColor = .secondaryLabelColor
        labelView.widthAnchor.constraint(equalToConstant: 72).isActive = true

        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        hotkeyValueLabel.textColor = .labelColor
        hotkeyValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

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
        updateHotkeyLabel()
        statusLabel.stringValue = config.authToken.isEmpty ? "未登录" : "已保存登录 token"
    }

    @objc private func save() {
        saveButton.isEnabled = false
        statusLabel.stringValue = "正在登录..."

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
            hotkeyKeyCode: previousConfig.hotkeyKeyCode,
            hotkeyModifiers: previousConfig.hotkeyModifiers
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
            statusLabel.stringValue = error.localizedDescription
            saveButton.isEnabled = true
            NSAlert(error: error).runModal()
        }
    }

    private func updateHotkeyLabel() {
        hotkeyValueLabel.stringValue = hotkeyDescription(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private func hotkeyDescription(keyCode: UInt32, modifiers: UInt32) -> String {
        "按住 Control 说话，松开结束"
    }
}
