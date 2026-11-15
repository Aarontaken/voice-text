import AppKit
import Foundation
import VoiceTextCore

enum RecordingState: Equatable {
    case idle
    case connecting
    case recording
    /// 已松手，等待服务端返回最终识别结果。
    case finalizing
    case error(String)
}

enum RecognitionPreviewState: Equatable {
    case hidden
    case preparing
    case listening
    case waiting
    case preview(String)
}

/// 一次语音输入的唯一编排者：建连 → 采音 → 结束 → 落字。
///
/// 豆包「一句话识别」只返回最终结果，因此这里不再维护流式增量的插入状态；
/// 中间文本只用于 HUD 预览。供应商差异被 `ASRSession` 隔开。
final class RecordingController {
    var onStateChange: ((RecordingState) -> Void)?
    var onPreviewChange: ((RecognitionPreviewState) -> Void)?

    private var configuration: ASRConfiguration
    private let audioCapture = AudioCaptureService()
    private let textInserter: TextInsertionService
    private var asrSession: ASRSession?
    private var recordingSessionID = UUID()
    private var insertedSegmentCount = 0
    private var didShowInsertionFailureAlert = false
    private var isPresentingMicrophoneAlert = false
    private var state: RecordingState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    init(configuration: ASRConfiguration, textInserter: TextInsertionService) {
        self.configuration = configuration
        self.textInserter = textInserter
    }

    func update(configuration: ASRConfiguration) {
        if state != .idle {
            abortSession()
        }
        self.configuration = configuration
    }

    func toggle() {
        switch state {
        case .idle, .error:
            start()
        case .connecting, .recording, .finalizing:
            stop()
        }
    }

    func start() {
        guard state == .idle || isErrorState else { return }

        guard configuration.hasAPIKey else {
            presentMissingAPIKeyAlert()
            state = .error("请先在设置中填写豆包 API Key")
            return
        }

        // 合盖时 macOS 在硬件层断开内建麦克风，采集链路不报错、只会一直上传静音。
        // 与其让用户对着「没有反应」猜半天，不如在建立连接前就拦下来并说清楚。
        guard !isPresentingMicrophoneAlert else { return }
        if let issue = MicrophoneAvailability.currentIssue() {
            VoiceTextLogger.log("Recording blocked by microphone preflight: \(issue.statusText)")
            presentMicrophoneUnavailableAlert(for: issue)
            state = .error(issue.statusText)
            return
        }

        VoiceTextLogger.log("Recording start requested resource=\(configuration.resource.rawValue)")
        let sessionID = UUID()
        recordingSessionID = sessionID
        insertedSegmentCount = 0
        didShowInsertionFailureAlert = false
        onPreviewChange?(.preparing)
        state = .connecting

        let session = DoubaoASRSession(configuration: configuration)
        session.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isCurrentSession(sessionID) else { return }
                self.handle(event, sessionID: sessionID)
            }
        }
        asrSession = session

        do {
            try session.start()
        } catch {
            VoiceTextLogger.log("Recording connect threw: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    func stop() {
        VoiceTextLogger.log("Recording stop requested state=\(state)")
        switch state {
        case .idle, .error:
            return
        case .connecting:
            finalizeSession()
        case .recording:
            audioCapture.stop()
            asrSession?.finish()
            onPreviewChange?(.waiting)
            state = .finalizing
        case .finalizing:
            return
        }
    }

    private var isErrorState: Bool {
        if case .error = state {
            return true
        }
        return false
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        recordingSessionID == sessionID && state != .idle
    }

    private func handle(_ event: ASREvent, sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        switch event {
        case .ready:
            startAudioCapture(sessionID: sessionID)
        case let .preview(text):
            onPreviewChange?(.preview(text))
        case let .segmentFinal(text):
            insertSegment(text)
        case let .completed(text, logId):
            handleFinalText(text, logId: logId)
        case let .failed(error):
            fail(error.message)
        }
    }

    private func startAudioCapture(sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        do {
            VoiceTextLogger.log("Audio capture start")
            try audioCapture.start(
                onPCM: { [weak self, sessionID] pcm in
                    guard let self, self.isCurrentSession(sessionID) else { return }
                    self.asrSession?.append(pcm)
                },
                onError: { [weak self, sessionID] error in
                    DispatchQueue.main.async {
                        guard let self, self.isCurrentSession(sessionID) else { return }
                        VoiceTextLogger.log("Audio capture failed: \(error.localizedDescription)")
                        self.fail(error.localizedDescription)
                    }
                }
            )
            guard isCurrentSession(sessionID) else { return }
            onPreviewChange?(.listening)
            playRecordingStartedSound()
            state = .recording
        } catch {
            guard isCurrentSession(sessionID) else { return }
            VoiceTextLogger.log("Audio capture start threw: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    /// 实时模式下每个已定稿分句立即落字，不等整段结束。
    private func insertSegment(_ text: String) {
        guard state != .idle else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        insertedSegmentCount += 1
        VoiceTextLogger.log("ASR realtime segment textCount=\(trimmed.count) inserted=\(insertedSegmentCount)")
        insertText(trimmed)
    }

    private func handleFinalText(_ text: String, logId: String?) {
        guard state != .idle else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        VoiceTextLogger.log("ASR final textCount=\(trimmed.count) logId=\(logId ?? "-")")

        if configuration.mode == .realtime {
            // 正常情况下分句已经插完；没有分句时用整句兜底，避免丢结果。
            if insertedSegmentCount == 0 {
                insertText(trimmed)
            }
        } else {
            insertText(trimmed)
        }

        finalizeSession()
    }

    private func insertText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let delta = textForInsertion(from: trimmed)
        do {
            try textInserter.insert(delta)
        } catch {
            VoiceTextLogger.log("Text insertion failed: \(error.localizedDescription)")
            // 实时模式每句都会尝试插入，失败提示只弹一次，避免连续对话框。
            guard !didShowInsertionFailureAlert else { return }
            didShowInsertionFailureAlert = true
            presentInsertionFailureAlert(for: error)
        }
    }

    private func finalizeSession() {
        audioCapture.stop()
        asrSession?.cancel()
        asrSession = nil
        recordingSessionID = UUID()
        onPreviewChange?(.hidden)
        state = .idle
        VoiceTextLogger.log("Recording session finalized")
    }

    private func abortSession() {
        audioCapture.stop()
        asrSession?.cancel()
        asrSession = nil
        recordingSessionID = UUID()
        onPreviewChange?(.hidden)
        state = .idle
    }

    private func fail(_ message: String) {
        audioCapture.stop()
        asrSession?.cancel()
        asrSession = nil
        recordingSessionID = UUID()
        onPreviewChange?(.hidden)
        VoiceTextLogger.log("Recording failed: \(message)")
        state = .error(message)
    }

    private func textForInsertion(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        guard let lastCharacter = trimmedText.last else { return trimmedText }

        if Self.terminalSeparators.contains(lastCharacter) {
            return trimmedText
        }
        if trimmedText.range(of: #"[A-Za-z0-9]$"#, options: .regularExpression) != nil {
            return trimmedText + " "
        }
        return trimmedText + "，"
    }

    private static let terminalSeparators = Set<Character>(
        "，。！？；：、,.!?;:\n "
    )

    private func playRecordingStartedSound() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func presentMissingAPIKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "需要豆包 API Key"
        alert.informativeText = "请打开菜单栏「设置」，填写火山引擎控制台的 API Key，并选择已开通的识别模型版本。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func presentMicrophoneUnavailableAlert(for issue: MicrophoneAvailability.Issue) {
        isPresentingMicrophoneAlert = true
        defer { isPresentingMicrophoneAlert = false }

        // 触发时焦点多半在别的 App 里，不主动激活的话对话框会被压在后面，等于没提示。
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = issue.title
        alert.informativeText = issue.detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开声音设置")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            openSoundInputSettings()
        }
    }

    /// 打开「系统设置 → 声音」，方便用户直接挑外置麦克风。
    /// 新老系统的锚点不通用（Ventura 前后各一套），逐个尝试。
    private func openSoundInputSettings() {
        let anchors = [
            "x-apple.systempreferences:com.apple.preference.sound",
            "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        ]
        for anchor in anchors {
            guard let url = URL(string: anchor) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        VoiceTextLogger.log("Failed to open Sound settings")
    }

    /// 针对不同失败原因给出可操作的提示：安全输入／缺权限时识别结果已经留在剪贴板，
    /// 不该再让用户以为「什么都没发生」。
    private func presentInsertionFailureAlert(for error: Error) {
        switch error as? TextInsertionService.InsertionError {
        case .secureInputActive:
            let alert = NSAlert()
            alert.messageText = "当前处于安全键盘输入"
            alert.informativeText = "焦点在密码框等启用了安全键盘输入的位置，系统会拦截模拟按键，因此没有自动写入。识别结果已复制到剪贴板，可按 ⌘V 手动粘贴。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        default:
            presentInsertionFailureAlert()
        }
    }

    private func presentInsertionFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "未能插入文字"
        alert.informativeText = "请确认已授予辅助功能权限，且光标位于可编辑的输入框中。若已复制到剪贴板，可尝试手动粘贴。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即授权")
        alert.addButton(withTitle: "好")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = textInserter.ensureAccessibilityPermission(prompt: true)
        }
    }
}
