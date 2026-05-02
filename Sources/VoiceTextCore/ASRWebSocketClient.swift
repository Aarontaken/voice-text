import Foundation

public enum ASRClientEvent: Sendable {
    case connected
    case recognition(RecognitionResult)
    case disconnected
    case failed(String)
}

public final class ASRWebSocketClient: NSObject, URLSessionWebSocketDelegate {
    private let configuration: ASRConfiguration
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var packetIndex = 0
    private let sendQueue = DispatchQueue(label: "ASRWebSocketClient.sendQueue")
    private let eventHandler: (ASRClientEvent) -> Void

    public init(
        configuration: ASRConfiguration,
        eventHandler: @escaping (ASRClientEvent) -> Void
    ) {
        self.configuration = configuration
        self.eventHandler = eventHandler
        super.init()
    }

    public func connect() throws {
        var request = try ASRProtocol.makeURLRequest(config: configuration)
        request.timeoutInterval = 15
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.connectionProxyDictionary = [:]
        VoiceTextLogger.log("ASR connect url=\(request.url?.absoluteString ?? "<nil>") cookie=\(!configuration.cookieHeader.isEmpty) extraHeaders=\(configuration.additionalHeaders.keys.sorted()) proxy=disabled")
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        receiveLoop()
    }

    public func sendInit() throws {
        VoiceTextLogger.log("ASR send init")
        try sendData(ASRProtocol.makeInitMessage(config: configuration))
    }

    public func sendAudioPacket(_ packet: Data) throws {
        let message = try ASRProtocol.makeAudioMessage(packet: packet, packetIndex: packetIndex)
        if packetIndex == 0 || packetIndex % 20 == 0 {
            VoiceTextLogger.log("ASR send audio packet index=\(packetIndex) bytes=\(packet.count)")
        }
        packetIndex += 1
        try sendData(message)
    }

    public func stop() {
        VoiceTextLogger.log("ASR stop")
        if let stopMessage = try? ASRProtocol.makeStopMessage() {
            try? sendData(stopMessage)
        }
        let taskToCancel = task
        let sessionToCancel = session
        task = nil
        session = nil
        packetIndex = 0
        sendQueue.asyncAfter(deadline: .now() + 2.0) {
            taskToCancel?.cancel(with: .normalClosure, reason: nil)
            sessionToCancel?.invalidateAndCancel()
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        VoiceTextLogger.log("ASR websocket opened")
        eventHandler(.connected)
        do {
            try sendInit()
        } catch {
            VoiceTextLogger.log("ASR send init failed: \(error.localizedDescription)")
            eventHandler(.failed(error.localizedDescription))
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        VoiceTextLogger.log("ASR websocket closed code=\(closeCode.rawValue)")
        eventHandler(.disconnected)
    }

    private func sendData(_ data: Data) throws {
        guard let task else { return }
        sendQueue.async {
            task.send(.data(data)) { error in
                if let error {
                    VoiceTextLogger.log("ASR send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                self.handle(message)
                self.receiveLoop()
            case let .failure(error):
                VoiceTextLogger.log("ASR receive failed: \(error.localizedDescription)")
                self.eventHandler(.failed(error.localizedDescription))
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        do {
            let text: String?
            switch message {
            case let .string(value):
                text = value
            case let .data(data):
                text = String(data: data, encoding: .utf8)
            @unknown default:
                text = nil
            }

            if let text, let result = try ASRProtocol.parseRecognitionMessage(text) {
                VoiceTextLogger.log("ASR recognition msgType=\(result.msgType) textCount=\(result.text.count)")
                eventHandler(.recognition(result))
            } else if let text {
                VoiceTextLogger.log("ASR message ignored tokens=\(ASRProtocol.tokensPreview(from: text)) raw=\(String(text.prefix(800)))")
            }
        } catch {
            let rawText: String
            switch message {
            case let .string(value):
                rawText = value
            case let .data(data):
                rawText = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            @unknown default:
                rawText = "<unknown message>"
            }
            VoiceTextLogger.log("ASR parse failed: \(error.localizedDescription) raw=\(String(rawText.prefix(800)))")
        }
    }
}
