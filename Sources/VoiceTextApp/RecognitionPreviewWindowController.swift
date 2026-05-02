import AppKit

final class RecognitionPreviewWindowController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private let container = NSVisualEffectView()
    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.94
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = makeContentView()
        return panel
    }()

    func showPreparing() {
        show(title: "准备中", text: "正在连接语音识别...")
    }

    func showListening() {
        show(title: "正在录音", text: "请开始说话")
    }

    func showWaiting() {
        show(title: "等待识别", text: "可以继续说下一句", isHint: true)
    }

    func showPreview(text: String) {
        show(title: "正在识别", text: text)
    }

    func hide() {
        window.orderOut(nil)
    }

    private func show(title: String, text: String, isHint: Bool = false) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            hide()
            return
        }

        titleLabel.stringValue = title
        textLabel.stringValue = normalizedText
        textLabel.textColor = isHint
            ? NSColor.white.withAlphaComponent(0.56)
            : NSColor.white.withAlphaComponent(0.95)
        window.setContentSize(preferredSize(for: normalizedText))
        positionWindow()
        window.orderFrontRegardless()
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = 0.35
        root.layer?.shadowRadius = 28
        root.layer?.shadowOffset = NSSize(width: 0, height: -10)

        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.appearance = NSAppearance(named: .vibrantDark)
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let glassTintView = NSView()
        glassTintView.wantsLayer = true
        glassTintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        glassTintView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.68)

        textLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        textLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleLabel, textLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(container)
        container.addSubview(glassTintView)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            glassTintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glassTintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassTintView.topAnchor.constraint(equalTo: container.topAnchor),
            glassTintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return root
    }

    private func preferredSize(for text: String) -> NSSize {
        let textWidth = min(max(CGFloat(text.count) * 18, 320), 680)
        return NSSize(width: textWidth, height: 92)
    }

    private func positionWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = window.frame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 120
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
