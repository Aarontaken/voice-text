import Foundation

/// 豆包返回的一个分句。
public struct DoubaoUtterance: Equatable, Sendable {
    public let text: String
    public let definite: Bool
    public let startTime: Int
    public let endTime: Int

    public init(text: String, definite: Bool, startTime: Int, endTime: Int) {
        self.text = text
        self.definite = definite
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// 豆包流式语音识别的一条响应。
public struct DoubaoResponse: Equatable, Sendable {
    public let code: Int
    public let messageType: Int
    public let isLastPackage: Bool
    public let payloadSequence: Int?
    public let event: Int?
    public let text: String
    public let utterances: [DoubaoUtterance]
    public let logId: String?
    public let audioDurationMilliseconds: Int?
    public let errorMessage: String?

    public init(
        code: Int = 0,
        messageType: Int = 9,
        isLastPackage: Bool = false,
        payloadSequence: Int? = nil,
        event: Int? = nil,
        text: String = "",
        utterances: [DoubaoUtterance] = [],
        logId: String? = nil,
        audioDurationMilliseconds: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.code = code
        self.messageType = messageType
        self.isLastPackage = isLastPackage
        self.payloadSequence = payloadSequence
        self.event = event
        self.text = text
        self.utterances = utterances
        self.logId = logId
        self.audioDurationMilliseconds = audioDurationMilliseconds
        self.errorMessage = errorMessage
    }
}

/// 豆包 v3 二进制 WebSocket 协议。
///
/// 一句话识别走 `bigmodel_nostream`，实时识别走 `bigmodel_async`，帧格式完全一致。
///
/// 帧结构：4 字节头 + 可选 sequence(4B) + 可选 event(4B) + payload_size(4B) + payload。
/// payload 为 gzip 压缩的 JSON，音频为 16kHz / 16bit / 单声道 PCM。
public enum DoubaoProtocol {
    public static func endpoint(for mode: ASRConfiguration.Mode) -> URL {
        switch mode {
        case .oneShot:
            return URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")!
        case .realtime:
            return URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
        }
    }

    public enum ProtocolError: Error, Equatable {
        case invalidResponse(String)
    }

    enum MessageType {
        static let fullClientRequest = 1
        static let audioOnlyRequest = 2
        static let serverFullResponse = 9
        static let serverErrorResponse = 15
    }

    enum Flags {
        static let positiveSequence = 0b0001
        static let negativeWithSequence = 0b0011
    }

    enum Serialization {
        static let json = 0b0001
    }

    enum Compression {
        static let gzip = 0b0001
    }

    public static func makeURLRequest(configuration: ASRConfiguration, requestId: String) throws -> URLRequest {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ASRServiceError(message: "请先在设置中填写豆包 API Key")
        }

        var request = URLRequest(url: endpoint(for: configuration.mode))
        request.timeoutInterval = 15
        request.addValue(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Api-Key")
        request.addValue(configuration.resource.rawValue, forHTTPHeaderField: "X-Api-Resource-Id")
        request.addValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        return request
    }

    /// 初始化帧：音频参数 + 识别参数，整包 gzip。
    public static func makeFullClientRequest(
        configuration: ASRConfiguration,
        sequence: Int32 = 1
    ) throws -> Data {
        var audio: [String: Any] = [
            "format": "pcm",
            "codec": "raw",
            "rate": 16_000,
            "bits": 16,
            "channel": 1
        ]
        if !configuration.language.isEmpty {
            audio["language"] = configuration.language
        }

        let endWindowSize = min(max(configuration.endWindowSize, 300), 5_000)
        let forceToSpeechTime = min(max(configuration.forceToSpeechTime, 0), 10_000)
        let isRealtime = configuration.mode == .realtime
        var requestOptions: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": configuration.enableITN,
            "enable_punc": configuration.enablePunc,
            "enable_ddc": configuration.enableDDC,
            "show_utterances": isRealtime ? true : configuration.showUtterances,
            "result_type": "full",
            "end_window_size": endWindowSize,
            "force_to_speech_time": forceToSpeechTime
        ]
        if isRealtime {
            // 二遍识别：每句话结束后用更稳定的结果替换实时文本。
            requestOptions["enable_nonstream"] = true
        }

        let payload: [String: Any] = [
            "user": ["uid": "voicetext-mac"],
            "audio": audio,
            "request": requestOptions
        ]

        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let compressed = try Gzip.compress(json)

        var frame = makeHeader(
            messageType: MessageType.fullClientRequest,
            flags: Flags.positiveSequence,
            serialization: Serialization.json,
            compression: Compression.gzip
        )
        appendInt32(sequence, to: &frame)
        appendUInt32(UInt32(compressed.count), to: &frame)
        frame.append(compressed)
        return frame
    }

    /// 音频帧：末包使用负数序号 + last 标志。
    public static func makeAudioRequest(pcm: Data, sequence: Int32, isLast: Bool) throws -> Data {
        let compressed = try Gzip.compress(pcm)
        var frame = makeHeader(
            messageType: MessageType.audioOnlyRequest,
            flags: isLast ? Flags.negativeWithSequence : Flags.positiveSequence,
            serialization: Serialization.json,
            compression: Compression.gzip
        )
        appendInt32(isLast ? -sequence : sequence, to: &frame)
        appendUInt32(UInt32(compressed.count), to: &frame)
        frame.append(compressed)
        return frame
    }

    public static func parseResponse(_ data: Data) throws -> DoubaoResponse {
        guard data.count >= 4 else {
            throw ProtocolError.invalidResponse("frame too short")
        }

        let bytes = [UInt8](data)
        let headerLength = Int(bytes[0] & 0x0F) * 4
        guard headerLength >= 4, bytes.count >= headerLength else {
            throw ProtocolError.invalidResponse("invalid header length")
        }

        let messageType = Int(bytes[1] >> 4)
        let flags = Int(bytes[1] & 0x0F)
        let serialization = Int(bytes[2] >> 4)
        let compression = Int(bytes[2] & 0x0F)

        var offset = headerLength

        func readInt32() throws -> Int32 {
            guard offset + 4 <= bytes.count else {
                throw ProtocolError.invalidResponse("truncated int32")
            }
            let value = Int32(
                UInt32(bytes[offset]) << 24
                    | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8
                    | UInt32(bytes[offset + 3])
            )
            offset += 4
            return value
        }

        func readUInt32() throws -> UInt32 {
            guard offset + 4 <= bytes.count else {
                throw ProtocolError.invalidResponse("truncated uint32")
            }
            let value = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            offset += 4
            return value
        }

        var sequence: Int?
        if flags & 0b0001 != 0 {
            sequence = Int(try readInt32())
        }
        let isLastPackage = flags & 0b0010 != 0
        var event: Int?
        if flags & 0b0100 != 0 {
            event = Int(try readInt32())
        }

        var code = 0
        var payloadSize = 0
        switch messageType {
        case MessageType.serverFullResponse:
            payloadSize = Int(try readUInt32())
        case MessageType.serverErrorResponse:
            code = Int(try readInt32())
            payloadSize = Int(try readUInt32())
        default:
            // 服务端可能插入 ack / 事件帧，当前客户端不消费，直接忽略。
            return DoubaoResponse(messageType: messageType, isLastPackage: false)
        }

        guard payloadSize >= 0, offset + payloadSize <= bytes.count else {
            throw ProtocolError.invalidResponse("payload size mismatch")
        }

        var payload = Data(bytes[offset..<(offset + payloadSize)])
        offset += payloadSize

        if compression == Compression.gzip, !payload.isEmpty {
            payload = try Gzip.decompress(payload)
        } else if compression != 0 {
            throw ProtocolError.invalidResponse("unsupported compression \(compression)")
        }

        var text = ""
        var utterances: [DoubaoUtterance] = []
        var logId: String?
        var audioDuration: Int?
        var errorMessage: String?

        if !payload.isEmpty {
            if serialization == Serialization.json, let json = try? JSONSerialization.jsonObject(with: payload) {
                if let root = json as? [String: Any] {
                    if let message = root["message"] as? String {
                        errorMessage = message
                    } else if let error = root["error"] as? String {
                        errorMessage = error
                    }

                    // 服务端 payload 顶层就是 audio_info / result；
                    // 旧样例里多包了一层 payload_msg，这里两种形状都兼容。
                    let payloadMessage = (root["payload_msg"] as? [String: Any]) ?? root

                    if let audioInfo = payloadMessage["audio_info"] as? [String: Any] {
                        audioDuration = audioInfo["duration"] as? Int
                    }

                    if let result = payloadMessage["result"] as? [String: Any] {
                        text = result["text"] as? String ?? ""
                        if let additions = result["additions"] as? [String: Any] {
                            logId = additions["log_id"] as? String
                        }
                        if let list = result["utterances"] as? [[String: Any]] {
                            utterances = list.compactMap { item in
                                guard let utteranceText = item["text"] as? String,
                                      !utteranceText.isEmpty else { return nil }
                                return DoubaoUtterance(
                                    text: utteranceText,
                                    definite: item["definite"] as? Bool ?? false,
                                    startTime: item["start_time"] as? Int ?? 0,
                                    endTime: item["end_time"] as? Int ?? 0
                                )
                            }
                        }
                    } else if let results = payloadMessage["result"] as? [[String: Any]] {
                        text = results.compactMap { $0["text"] as? String }.joined()
                        logId = results
                            .compactMap { ($0["additions"] as? [String: Any])?["log_id"] as? String }
                            .first
                    }
                } else if let textValue = json as? String {
                    errorMessage = textValue
                }
            } else if let raw = String(data: payload, encoding: .utf8) {
                errorMessage = raw
            }
        }

        return DoubaoResponse(
            code: code,
            messageType: messageType,
            isLastPackage: isLastPackage,
            payloadSequence: sequence,
            event: event,
            text: text,
            utterances: utterances,
            logId: logId,
            audioDurationMilliseconds: audioDuration,
            errorMessage: errorMessage
        )
    }

    private static func makeHeader(
        messageType: Int,
        flags: Int,
        serialization: Int,
        compression: Int
    ) -> Data {
        Data([
            UInt8(0b0001_0001),
            UInt8((messageType << 4) | flags),
            UInt8((serialization << 4) | compression),
            0x00
        ])
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
