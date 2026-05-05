import AppKit
import Foundation
import VoiceTextCore

enum RecordingState: Equatable {
    case idle
    case connecting
    case recording
    /// User ended recording; waiting briefly for final ASR messages before tearing down the socket.
    case draining
    case error(String)
}

enum RecognitionPreviewState: Equatable {
    case hidden
    case preparing
    case listening
    case waiting
    case preview(String)
}

final class RecordingController {
    var onStateChange: ((RecordingState) -> Void)?
    var onPreviewChange: ((RecognitionPreviewState) -> Void)?

    private var configuration: ASRConfiguration
    private let audioCapture = AudioCaptureService()
    private let textInserter: TextInsertionService
    private let settingsStore: SettingsStore
    private var asrClient: ASRWebSocketClient?
    private var startTask: Task<Void, Never>?
    private var recordingSessionID = UUID()
    private var currentSegmentFinalInserted = false
    /// Latest streaming (non-final) ASR text shown in the preview; flushed on stop if no final arrived yet.
    private var pendingNonFinalPreviewText: String?
    /// True after `sendSessionStop()` during drain; `finalizeSessionEnd` only closes the socket (no duplicate stop frame).
    private var endSessionStopAlreadySent = false
    private var drainTimeoutWorkItem: DispatchWorkItem?
    /// 单次录音会话内最多提示一次，避免连续多句识别时反复弹窗。
    private var didShowAccessibilityMissingAlertForThisRecording = false
    private var state: RecordingState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    init(configuration: ASRConfiguration, textInserter: TextInsertionService, settingsStore: SettingsStore) {
        self.configuration = configuration
        self.textInserter = textInserter
        self.settingsStore = settingsStore
    }

    func update(configuration: ASRConfiguration) {
        if state == .connecting || state == .recording || state == .draining {
            stop()
        }
        self.configuration = configuration
    }

    func toggle() {
        switch state {
        case .idle, .error:
            start()
        case .connecting, .recording, .draining:
            stop()
        }
    }

    func start() {
        guard state == .idle || isErrorState else { return }
        VoiceTextLogger.log("Recording start requested")
        let sessionID = UUID()
        recordingSessionID = sessionID
        didShowAccessibilityMissingAlertForThisRecording = false
        onPreviewChange?(.preparing)
        pendingNonFinalPreviewText = nil
        endSessionStopAlreadySent = false
        cancelDrainTimeout()
        currentSegmentFinalInserted = false
        state = .connecting

        startTask?.cancel()
        startTask = Task { [weak self, sessionID] in
            await self?.refreshCookieThenConnect(sessionID: sessionID)
        }
    }

    @MainActor
    private func refreshCookieThenConnect(sessionID: UUID) async {
        do {
            let refreshedConfiguration = try await AuthCookieClient.refreshCookies(for: configuration)
            guard !Task.isCancelled, isCurrentSession(sessionID) else { return }
            configuration = refreshedConfiguration
            try? settingsStore.save(refreshedConfiguration)
            connect(configuration: refreshedConfiguration, sessionID: sessionID)
        } catch {
            guard !Task.isCancelled, isCurrentSession(sessionID) else { return }
            VoiceTextLogger.log("Auth cookie refresh failed: \(error.localizedDescription)")
            connect(configuration: configuration, sessionID: sessionID)
        }
    }

    private func connect(configuration: ASRConfiguration, sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        let client = ASRWebSocketClient(configuration: configuration) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isCurrentSession(sessionID) else { return }
                self.handle(event, sessionID: sessionID)
            }
        }
        asrClient = client

        do {
            try client.connect()
        } catch {
            guard isCurrentSession(sessionID) else { return }
            VoiceTextLogger.log("Recording connect threw: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    func stop() {
        VoiceTextLogger.log("Recording stop requested")
        switch state {
        case .idle, .error:
            return
        case .draining:
            finalizeSessionEnd()
        case .connecting:
            finalizeSessionEnd()
        case .recording:
            beginDrainingStop()
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

    private func cancelDrainTimeout() {
        drainTimeoutWorkItem?.cancel()
        drainTimeoutWorkItem = nil
    }

    private func beginDrainingStop() {
        guard state == .recording else { return }
        VoiceTextLogger.log("Recording entering drain for final ASR messages")
        startTask?.cancel()
        startTask = nil
        audioCapture.stop()
        endSessionStopAlreadySent = true
        asrClient?.sendSessionStop()
        state = .draining
        let sessionID = recordingSessionID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .draining, self.recordingSessionID == sessionID else { return }
            self.finalizeSessionEnd()
        }
        drainTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func finalizeSessionEnd() {
        cancelDrainTimeout()
        switch state {
        case .connecting, .recording, .draining:
            break
        case .idle, .error:
            return
        }
        flushPendingPreviewIfNeeded()
        startTask?.cancel()
        startTask = nil
        recordingSessionID = UUID()
        audioCapture.stop()
        if endSessionStopAlreadySent {
            endSessionStopAlreadySent = false
            asrClient?.closeConnection()
        } else {
            asrClient?.stop()
        }
        asrClient = nil
        onPreviewChange?(.hidden)
        currentSegmentFinalInserted = false
        state = .idle
        VoiceTextLogger.log("Recording session finalized")
    }

    private func handle(_ event: ASRClientEvent, sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        switch event {
        case .connected:
            startAudioCapture(sessionID: sessionID)
        case let .recognition(result):
            insert(result)
        case .disconnected:
            finalizeSessionEnd()
        case let .failed(message):
            fail(message)
        }
    }

    private func startAudioCapture(sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        do {
            VoiceTextLogger.log("Audio capture start")
            try audioCapture.start(
                onPacket: { [weak self, sessionID] packet in
                    guard self?.isCurrentSession(sessionID) == true else { return }
                    do {
                        try self?.asrClient?.sendAudioPacket(packet)
                    } catch {
                        DispatchQueue.main.async {
                            guard self?.isCurrentSession(sessionID) == true else { return }
                            VoiceTextLogger.log("Audio packet send failed: \(error.localizedDescription)")
                            self?.fail(error.localizedDescription)
                        }
                    }
                },
                onError: { [weak self, sessionID] error in
                    DispatchQueue.main.async {
                        guard self?.isCurrentSession(sessionID) == true else { return }
                        VoiceTextLogger.log("Audio capture failed: \(error.localizedDescription)")
                        self?.fail(error.localizedDescription)
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

    private func insert(_ result: RecognitionResult) {
        guard result.isFinal else {
            currentSegmentFinalInserted = false
            pendingNonFinalPreviewText = result.text
            onPreviewChange?(.preview(result.text))
            VoiceTextLogger.log("ASR streaming preview textCount=\(result.text.count)")
            return
        }
        pendingNonFinalPreviewText = nil
        guard !currentSegmentFinalInserted else {
            VoiceTextLogger.log("ASR duplicate final ignored textCount=\(result.text.count)")
            return
        }
        currentSegmentFinalInserted = true
        let delta = textForInsertion(from: result.text)
        onPreviewChange?(.waiting)
        guard !delta.isEmpty else { return }
        VoiceTextLogger.log("ASR final insert textCount=\(result.text.count) insertCount=\(delta.count)")
        warnIfAccessibilityMissingBeforeInsert()
        do {
            try textInserter.insert(delta)
        } catch {
            VoiceTextLogger.log("Text insertion failed: \(error.localizedDescription)")
            presentInsertionFailureAlert()
        }
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

    private func fail(_ message: String) {
        cancelDrainTimeout()
        flushPendingPreviewIfNeeded()
        VoiceTextLogger.log("Recording failed: \(message)")
        startTask?.cancel()
        startTask = nil
        recordingSessionID = UUID()
        audioCapture.stop()
        if endSessionStopAlreadySent {
            endSessionStopAlreadySent = false
            asrClient?.closeConnection()
        } else {
            asrClient?.stop()
        }
        asrClient = nil
        onPreviewChange?(.hidden)
        state = .error(message)
    }

    private func playRecordingStartedSound() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    /// Inserts preview-only (non-final) text so it is not lost when recording ends before a final result.
    private func flushPendingPreviewIfNeeded() {
        let raw = pendingNonFinalPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingNonFinalPreviewText = nil
        guard !raw.isEmpty else { return }
        let delta = textForInsertion(from: raw)
        guard !delta.isEmpty else { return }
        VoiceTextLogger.log("ASR flush pending preview on end textCount=\(raw.count) insertCount=\(delta.count)")
        warnIfAccessibilityMissingBeforeInsert()
        do {
            try textInserter.insert(delta)
        } catch {
            VoiceTextLogger.log("Text insertion failed on pending preview flush: \(error.localizedDescription)")
            presentInsertionFailureAlert()
        }
    }

    private func warnIfAccessibilityMissingBeforeInsert() {
        guard !textInserter.ensureAccessibilityPermission(prompt: false) else { return }
        guard !didShowAccessibilityMissingAlertForThisRecording else { return }
        didShowAccessibilityMissingAlertForThisRecording = true

        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "未开启时，识别结果往往无法写入当前输入框（模拟粘贴也会被系统拦截）。请在「系统设置 → 隐私与安全性 → 辅助功能」中为 VoiceText 打开开关。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即授权")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = textInserter.ensureAccessibilityPermission(prompt: true)
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
