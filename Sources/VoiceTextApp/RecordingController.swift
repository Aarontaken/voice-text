import AppKit
import Foundation
import VoiceTextCore

enum RecordingState: Equatable {
    case idle
    case connecting
    case recording
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
        if state == .connecting || state == .recording {
            stop()
        }
        self.configuration = configuration
    }

    func toggle() {
        switch state {
        case .idle, .error:
            start()
        case .connecting, .recording:
            stop()
        }
    }

    func start() {
        guard state == .idle || isErrorState else { return }
        VoiceTextLogger.log("Recording start requested")
        let sessionID = UUID()
        recordingSessionID = sessionID
        onPreviewChange?(.preparing)
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
        startTask?.cancel()
        startTask = nil
        recordingSessionID = UUID()
        audioCapture.stop()
        asrClient?.stop()
        asrClient = nil
        onPreviewChange?(.hidden)
        currentSegmentFinalInserted = false
        state = .idle
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

    private func handle(_ event: ASRClientEvent, sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        switch event {
        case .connected:
            startAudioCapture(sessionID: sessionID)
        case let .recognition(result):
            insert(result)
        case .disconnected:
            stop()
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
            onPreviewChange?(.preview(result.text))
            VoiceTextLogger.log("ASR streaming preview textCount=\(result.text.count)")
            return
        }
        guard !currentSegmentFinalInserted else {
            VoiceTextLogger.log("ASR duplicate final ignored textCount=\(result.text.count)")
            return
        }
        currentSegmentFinalInserted = true
        let delta = textForInsertion(from: result.text)
        onPreviewChange?(.waiting)
        guard !delta.isEmpty else { return }
        VoiceTextLogger.log("ASR final insert textCount=\(result.text.count) insertCount=\(delta.count)")
        do {
            try textInserter.insert(delta)
        } catch {
            VoiceTextLogger.log("Text insertion failed: \(error.localizedDescription)")
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
        VoiceTextLogger.log("Recording failed: \(message)")
        startTask?.cancel()
        startTask = nil
        recordingSessionID = UUID()
        audioCapture.stop()
        asrClient?.stop()
        asrClient = nil
        onPreviewChange?(.hidden)
        state = .error(message)
    }

    private func playRecordingStartedSound() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
}
