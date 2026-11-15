import Foundation

/// 豆包流式语音识别的 WebSocket 会话，支持两种模式：
///
/// - 一句话识别（`bigmodel_nostream`）：松手后返回整句，`completed` 时一次性落字；
/// - 实时识别（`bigmodel_async`）：边说边返回分句，`definite` 分句通过 `segmentFinal` 逐句落字。
///
/// 两种模式共用同一套二进制帧、gzip、鉴权和 PCM 分包。
public final class DoubaoASRSession: NSObject, ASRSession, URLSessionWebSocketDelegate {
    public var onEvent: ((ASREvent) -> Void)?

    private let configuration: ASRConfiguration
    private let mode: ASRConfiguration.Mode
    private let requestId = UUID().uuidString
    private let sendQueue = DispatchQueue(label: "com.voicetext.doubao.session")
    private var chunker = PCMChunker()
    private var sequence: Int32 = 1
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    // 以下状态只在 sendQueue 上读写。
    private var didSendFullRequest = false
    private var didReceiveFirstResponse = false
    private var didFinish = false
    private var sentAudioPackets = 0
    private var isClosed = false
    private var lastPreviewText = ""
    private var utteranceTracker = DefiniteUtteranceTracker()
    private var emittedSegmentCount = 0
    private var firstResponseTimeout: DispatchWorkItem?
    private var finalResponseTimeout: DispatchWorkItem?

    public init(configuration: ASRConfiguration) {
        self.configuration = configuration
        self.mode = configuration.mode
        super.init()
    }

    deinit {
        firstResponseTimeout?.cancel()
        finalResponseTimeout?.cancel()
    }

    public func start() throws {
        let request = try DoubaoProtocol.makeURLRequest(configuration: configuration, requestId: requestId)
        VoiceTextLogger.log("Doubao connect mode=\(configuration.mode.rawValue) url=\(request.url?.absoluteString ?? "<nil>") resource=\(configuration.resource.rawValue) requestId=\(requestId)")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.connectionProxyDictionary = [:]

        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        receiveLoop()
    }

    public func append(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed, self.didReceiveFirstResponse else { return }
            let chunks = self.chunker.append(pcm)
            for chunk in chunks {
                self.sendAudioOnQueue(chunk, isLast: false)
            }
        }
    }

    public func finish() {
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed, !self.didFinish else { return }
            self.didFinish = true

            let remaining = self.chunker.finish()
            guard !remaining.isEmpty else {
                VoiceTextLogger.log("Doubao finish without audio")
                self.completeOnQueue(text: self.lastPreviewText, logId: nil)
                return
            }

            for (index, chunk) in remaining.enumerated() {
                guard !self.isClosed else { return }
                self.sendAudioOnQueue(chunk, isLast: index == remaining.count - 1)
            }
            guard !self.isClosed else { return }
            self.scheduleFinalResponseTimeout()
        }
    }

    public func cancel() {
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.isClosed = true
            self.cancelTimeouts()
            self.closeTransport()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        VoiceTextLogger.log("Doubao websocket opened")
        if let http = webSocketTask.response as? HTTPURLResponse {
            VoiceTextLogger.log("Doubao handshake status=\(http.statusCode)")
        }
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed, !self.didSendFullRequest else { return }
            do {
                let frame = try DoubaoProtocol.makeFullClientRequest(
                    configuration: self.configuration,
                    sequence: self.sequence
                )
                self.sequence += 1
                self.didSendFullRequest = true
                self.task?.send(.data(frame)) { [weak self] error in
                    guard let self, let error else { return }
                    self.sendQueue.async {
                        self.failOnQueue("初始化请求发送失败：\(error.localizedDescription)")
                    }
                }
                self.scheduleFirstResponseTimeout()
            } catch {
                self.failOnQueue("初始化请求构造失败：\(error.localizedDescription)")
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        VoiceTextLogger.log("Doubao websocket closed code=\(closeCode.rawValue)")
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.failOnQueue("连接已关闭（\(closeCode.rawValue)）")
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        VoiceTextLogger.log(
            "Doubao websocket completed error=\(error.localizedDescription) httpStatus=\(statusCode.map(String.init) ?? "-")"
        )

        let message: String
        switch statusCode {
        case 401:
            message = "豆包鉴权失败（HTTP 401），请检查 API Key"
        case 403:
            message = "没有访问权限（HTTP 403），请确认模型版本与已开通资源一致"
        default:
            message = "连接异常：\(error.localizedDescription)"
        }

        sendQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.failOnQueue(message)
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        sendQueue.async { [weak self] in
            guard let self, !self.isClosed, let task = self.task else { return }
            task.receive { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(message):
                    self.sendQueue.async {
                        guard !self.isClosed else { return }
                        switch message {
                        case let .data(data):
                            self.handleResponseOnQueue(data)
                        case .string:
                            self.failOnQueue("服务端返回了文本帧，协议要求二进制帧")
                        @unknown default:
                            break
                        }
                    }
                    self.receiveLoop()
                case let .failure(error):
                    self.sendQueue.async {
                        guard !self.isClosed else { return }
                        self.failOnQueue("连接中断：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleResponseOnQueue(_ data: Data) {
        guard !isClosed else { return }

        let response: DoubaoResponse
        do {
            response = try DoubaoProtocol.parseResponse(data)
        } catch {
            failOnQueue("识别响应解析失败：\(error.localizedDescription)")
            return
        }

        VoiceTextLogger.log(
            "Doubao response type=\(response.messageType) code=\(response.code) last=\(response.isLastPackage) seq=\(response.payloadSequence.map(String.init) ?? "-") audioMs=\(response.audioDurationMilliseconds.map(String.init) ?? "-") textCount=\(response.text.count)"
        )

        if response.messageType == 15 || response.code != 0 {
            failOnQueue(response.errorMessage ?? "豆包服务返回错误码 \(response.code)", code: response.code)
            return
        }

        if !didReceiveFirstResponse {
            didReceiveFirstResponse = true
            firstResponseTimeout?.cancel()
            firstResponseTimeout = nil
            emit(.ready)
        }

        if !response.text.isEmpty {
            lastPreviewText = response.text
            emit(.preview(response.text))
        }

        if mode == .realtime {
            let segments = utteranceTracker.takeNewDefinite(response.utterances)
            for segment in segments {
                emittedSegmentCount += 1
                emit(.segmentFinal(segment))
            }
        }

        if response.isLastPackage {
            // 实时模式下如果服务端没给分句，把整句作为唯一分句兜底。
            if mode == .realtime, emittedSegmentCount == 0 {
                let fallbackText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackText.isEmpty {
                    emittedSegmentCount += 1
                    emit(.segmentFinal(fallbackText))
                }
            }

            completeOnQueue(
                text: response.text.isEmpty ? lastPreviewText : response.text,
                logId: response.logId
            )
        }
    }

    // MARK: - Send

    private func sendAudioOnQueue(_ pcm: Data, isLast: Bool) {
        do {
            let frame = try DoubaoProtocol.makeAudioRequest(
                pcm: pcm,
                sequence: sequence,
                isLast: isLast
            )
            if !isLast {
                sentAudioPackets += 1
                if sentAudioPackets == 1 || sentAudioPackets % 10 == 0 {
                    VoiceTextLogger.log("Doubao audio sent packets=\(sentAudioPackets) seq=\(sequence) bytes=\(pcm.count)")
                }
                sequence += 1
            } else {
                VoiceTextLogger.log("Doubao audio last packet seq=\(-sequence) bytes=\(pcm.count)")
            }
            task?.send(.data(frame)) { [weak self] error in
                guard let self, let error else { return }
                self.sendQueue.async {
                    self.failOnQueue("音频发送失败：\(error.localizedDescription)")
                }
            }
        } catch {
            failOnQueue("音频编码失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Termination

    private func completeOnQueue(text: String, logId: String?) {
        guard !isClosed else { return }
        isClosed = true
        cancelTimeouts()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        VoiceTextLogger.log("Doubao completed textCount=\(trimmed.count) logId=\(logId ?? "-")")
        emit(.completed(text: text, logId: logId))
        closeTransport()
    }

    private func failOnQueue(_ message: String, code: Int? = nil) {
        guard !isClosed else { return }
        isClosed = true
        cancelTimeouts()
        VoiceTextLogger.log("Doubao failed: \(message) code=\(code.map(String.init) ?? "-")")
        emit(.failed(ASRServiceError(message: message, code: code)))
        closeTransport()
    }

    private func emit(_ event: ASREvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func closeTransport() {
        let taskToClose = task
        let sessionToClose = session
        task = nil
        session = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            taskToClose?.cancel(with: .normalClosure, reason: nil)
            sessionToClose?.invalidateAndCancel()
        }
    }

    private func scheduleFirstResponseTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosed, !self.didReceiveFirstResponse else { return }
            self.failOnQueue("豆包服务连接超时")
        }
        firstResponseTimeout?.cancel()
        firstResponseTimeout = workItem
        sendQueue.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func scheduleFinalResponseTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosed else { return }
            self.failOnQueue("等待识别结果超时")
        }
        finalResponseTimeout?.cancel()
        finalResponseTimeout = workItem
        sendQueue.asyncAfter(deadline: .now() + 20, execute: workItem)
    }

    private func cancelTimeouts() {
        firstResponseTimeout?.cancel()
        firstResponseTimeout = nil
        finalResponseTimeout?.cancel()
        finalResponseTimeout = nil
    }
}
