import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var accessibilityStatusProvider: (() -> Bool)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleItem = NSMenuItem(title: "开始识别", action: #selector(toggle), keyEquivalent: "")
    private let stateItem = NSMenuItem(title: "空闲", action: nil, keyEquivalent: "")
    private let hotkeyItem = NSMenuItem(title: "快捷键：按住 Control 说话，松开结束；双击 Control 开始/停止", action: nil, keyEquivalent: "")
    private let accessibilityStatusItem = NSMenuItem(title: "辅助功能：未知", action: nil, keyEquivalent: "")
    private var hotkeyDescription = "按住 Control 说话，松开结束；双击 Control 开始/停止"
    private var didBecomeActiveObserver: NSObjectProtocol?

    override init() {
        super.init()
        item.button?.title = "VT"
        let menu = NSMenu()
        menu.delegate = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",").targeting(self))
        accessibilityStatusItem.isEnabled = false
        menu.addItem(accessibilityStatusItem)
        menu.addItem(NSMenuItem(title: "授权辅助功能", action: #selector(requestAccessibility), keyEquivalent: "").targeting(self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q").targeting(self))
        item.menu = menu

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAccessibilityStatus()
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAccessibilityStatus()
    }

    func update(state: RecordingState) {
        updateAccessibilityStatus()
        switch state {
        case .idle:
            item.button?.title = "VT"
            stateItem.title = "空闲"
            toggleItem.title = "开始识别（\(hotkeyDescription)）"
        case .connecting:
            item.button?.title = "…"
            stateItem.title = "连接中"
            toggleItem.title = "停止识别"
        case .recording:
            item.button?.title = "REC"
            stateItem.title = "识别中"
            toggleItem.title = "停止识别"
        case .draining:
            item.button?.title = "…"
            stateItem.title = "收尾中"
            toggleItem.title = "停止识别"
        case let .error(message):
            item.button?.title = "!"
            stateItem.title = "错误：\(message)"
            toggleItem.title = "重新开始"
        }
    }

    func updateAccessibilityStatus() {
        let isTrusted = accessibilityStatusProvider?() ?? false
        accessibilityStatusItem.title = isTrusted ? "辅助功能：已开启" : "辅助功能：未开启"
    }

    func updateHotkeyDescription(_ description: String) {
        hotkeyDescription = description
        hotkeyItem.title = "快捷键：\(description)"
        if toggleItem.title.hasPrefix("开始识别") {
            toggleItem.title = "开始识别（\(description)）"
        }
    }

    @objc private func toggle() {
        onToggle?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
        updateAccessibilityStatus()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
