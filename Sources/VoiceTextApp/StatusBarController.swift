import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var accessibilityStatusProvider: (() -> Bool)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleItem = NSMenuItem(title: "开始识别", action: #selector(toggle), keyEquivalent: "")
    private let stateItem = NSMenuItem(title: "空闲", action: nil, keyEquivalent: "")
    private let hotkeyItem = NSMenuItem(title: "快捷键：按住 Option (⌥) 说话，松开结束；双击 Control 开始/停止", action: nil, keyEquivalent: "")
    private let accessibilityStatusItem = NSMenuItem(title: "辅助功能：未知", action: nil, keyEquivalent: "")
    private var hotkeyDescription = "按住 Option (⌥) 说话，松开结束；双击 Control 开始/停止"
    private var didBecomeActiveObserver: NSObjectProtocol?

    override init() {
        super.init()
        item.button?.toolTip = "VoiceText"
        item.button?.setAccessibilityLabel("VoiceText")
        applyStatusButton(image: StatusBarAssets.templateIcon, title: "")
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
            applyStatusButton(image: StatusBarAssets.templateIcon, title: "")
            stateItem.title = "空闲"
            toggleItem.title = "开始识别（\(hotkeyDescription)）"
        case .connecting:
            applyStatusButton(image: nil, title: "…")
            stateItem.title = "连接中"
            toggleItem.title = "停止识别"
        case .recording:
            applyStatusButton(image: nil, title: "REC")
            stateItem.title = "识别中"
            toggleItem.title = "停止识别"
        case .draining:
            applyStatusButton(image: nil, title: "…")
            stateItem.title = "收尾中"
            toggleItem.title = "停止识别"
        case let .error(message):
            applyStatusButton(image: nil, title: "!")
            stateItem.title = "错误：\(message)"
            toggleItem.title = "重新开始"
        }
    }

    private func applyStatusButton(image: NSImage?, title: String) {
        let button = item.button
        button?.image = image
        button?.title = title
        if image != nil, title.isEmpty {
            button?.imagePosition = .imageOnly
        } else {
            button?.imagePosition = .noImage
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

private enum StatusBarAssets {
    /// 菜单栏模板图：较大声波 + 两条略细横线，整图单色由系统着色。
    static let templateIcon: NSImage = makeTemplateIcon()

    private static func makeTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let pad = rect.width * 0.1
            let inner = rect.insetBy(dx: pad, dy: pad)
            let waveLineWidth = max(1.35, rect.width * 0.095)
            let textLineWidth = max(0.65, rect.width * 0.048)

            let yMid = inner.midY
            let waveWidth = inner.width * 0.58
            let amp = inner.height * 0.36
            let steps = 20

            let wavePath = NSBezierPath()
            wavePath.lineWidth = waveLineWidth
            wavePath.lineCapStyle = .round
            wavePath.lineJoinStyle = .round
            NSColor.black.setStroke()
            for i in 0 ... steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = inner.minX + t * waveWidth
                let y = yMid + sin(t * .pi * 2) * amp
                let p = NSPoint(x: x, y: y)
                if i == 0 {
                    wavePath.move(to: p)
                } else {
                    wavePath.line(to: p)
                }
            }
            wavePath.stroke()

            let xStart = inner.minX + inner.width * 0.62
            let xEnd = inner.minX + inner.width * 0.92
            let textPath = NSBezierPath()
            textPath.lineWidth = textLineWidth
            textPath.lineCapStyle = .round
            NSColor.black.setStroke()
            for frac in [-0.14, 0.14] as [CGFloat] {
                let y = yMid + frac * inner.height
                textPath.move(to: NSPoint(x: xStart, y: y))
                textPath.line(to: NSPoint(x: xEnd, y: y))
            }
            textPath.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
