import AppKit
import QuartzCore

final class RecognitionPreviewWindowController {
    private enum Indicator {
        case waveform
        case spinner
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private let container = NSVisualEffectView()
    private let waveform = WaveformView()
    private let spinner = NSProgressIndicator()
    private let indicatorHolder = NSView()
    private lazy var window: NSPanel = makePanel()
    private var hideWorkItem: DispatchWorkItem?

    deinit {
        waveform.stop()
        hideWorkItem?.cancel()
    }

    // MARK: - Public states

    func showPreparing() {
        present(title: "正在连接", text: "准备语音识别…", indicator: .spinner, isHint: true)
    }

    func showListening() {
        present(title: "正在聆听", text: "请开始说话", indicator: .waveform, isHint: true)
    }

    func showWaiting() {
        present(title: "正在识别", text: "正在整理文字…", indicator: .spinner, isHint: true)
    }

    func showPreview(text: String) {
        present(title: "识别中", text: text, indicator: .waveform, isHint: false)
    }

    func hide() {
        guard window.isVisible else { return }
        waveform.stop()

        let workItem = DispatchWorkItem { [weak self] in
            self?.window.orderOut(nil)
            self?.window.alphaValue = 0
        }
        hideWorkItem?.cancel()
        hideWorkItem = workItem

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            workItem.perform()
        }
    }

    // MARK: - Presentation

    private func present(title: String, text: String, indicator: Indicator, isHint: Bool) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            hide()
            return
        }

        // 先触发窗口与字体初始化，再测量文本宽度，否则首次展示会用默认字号算错尺寸。
        let panel = window

        hideWorkItem?.cancel()
        hideWorkItem = nil

        titleLabel.stringValue = title
        textLabel.stringValue = normalizedText
        textLabel.textColor = isHint
            ? NSColor.white.withAlphaComponent(0.62)
            : NSColor.white.withAlphaComponent(0.96)
        updateIndicator(indicator)

        let size = preferredSize(for: normalizedText)
        textLabel.preferredMaxLayoutWidth = max(200, size.width - 100)
        panel.setFrame(frame(for: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else if panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func updateIndicator(_ indicator: Indicator) {
        switch indicator {
        case .waveform:
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            waveform.isHidden = false
            waveform.start()
        case .spinner:
            waveform.stop()
            waveform.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        }
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.contentView = makeContentView()
        return panel
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.appearance = NSAppearance(named: .vibrantDark)
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        titleLabel.maximumNumberOfLines = 1

        textLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        textLabel.textColor = NSColor.white.withAlphaComponent(0.96)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 2
        textLabel.cell?.wraps = true

        indicatorHolder.translatesAutoresizingMaskIntoConstraints = false
        indicatorHolder.widthAnchor.constraint(equalToConstant: 24).isActive = true
        indicatorHolder.heightAnchor.constraint(equalToConstant: 24).isActive = true

        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.isHidden = true
        indicatorHolder.addSubview(waveform)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        indicatorHolder.addSubview(spinner)

        let textStack = NSStackView(views: [titleLabel, textLabel])
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        let contentStack = NSStackView(views: [indicatorHolder, textStack])
        contentStack.orientation = .horizontal
        contentStack.spacing = 12
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(container)
        container.addSubview(tint)
        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: root.topAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            waveform.centerXAnchor.constraint(equalTo: indicatorHolder.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: indicatorHolder.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 22),
            waveform.heightAnchor.constraint(equalToConstant: 22),

            spinner.centerXAnchor.constraint(equalTo: indicatorHolder.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: indicatorHolder.centerYAnchor),

            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            contentStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return root
    }

    private func preferredSize(for text: String) -> NSSize {
        let maxTextWidth: CGFloat = 520
        let font = textLabel.font ?? .systemFont(ofSize: 17, weight: .semibold)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let lineHeight = max(ceil(font.ascender - font.descender + font.leading), 1)
        let lines = max(1, min(2, Int(ceil(bounding.height / lineHeight))))
        let width = min(max(340, ceil(bounding.width) + 100), 680)
        let height: CGFloat = lines > 1 ? 96 : 84
        return NSSize(width: width, height: height)
    }

    private func frame(for size: NSSize) -> NSRect {
        let screen = presentationScreen()
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 96
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func presentationScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

// MARK: - Waveform

private final class WaveformView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.26
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barCount = 5
        let barWidth: CGFloat = 2.6
        let available = bounds.width - CGFloat(barCount) * barWidth
        let gap = barCount > 1 ? available / CGFloat(barCount - 1) : 0
        let midY = bounds.midY

        NSColor.white.withAlphaComponent(0.92).setFill()

        for index in 0..<barCount {
            let wave = (sin(phase + CGFloat(index) * 0.82) + 1) / 2
            let height = 4 + wave * (bounds.height - 7)
            let x = CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
