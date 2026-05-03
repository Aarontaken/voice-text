import Foundation

public struct RecognitionResult: Codable, Equatable, Sendable {
    public let text: String
    public let msgType: Int

    public var isFinal: Bool {
        msgType == 1
    }
}

public enum ASRProtocol {
    public enum ProtocolError: Error, Equatable {
        case invalidURL
    }

    private struct InitMessage: Encodable {
        let type = 1
        let text: String
        let params: [String: String]
    }

    private struct AudioMessage: Encodable {
        let type = 2
        let packet: String
        let packetIndex: Int
    }

    private struct StopMessage: Encodable {
        let type = 3
    }

    public static func makeWebSocketURL(
        config: ASRConfiguration,
        timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = config.environment.speechHost
        components.path = "/apeman-cn-voice-input/asr"
        components.queryItems = [
            URLQueryItem(name: "userId", value: config.userId),
            URLQueryItem(name: "timestamp", value: String(timestampMillis))
        ]

        guard let url = components.url else {
            throw ProtocolError.invalidURL
        }
        return url
    }

    public static func makeURLRequest(config: ASRConfiguration) throws -> URLRequest {
        let url = try makeWebSocketURL(config: config)
        var request = URLRequest(url: url)
        request.addValue("Upgrade", forHTTPHeaderField: "Connection")
        request.addValue(url.absoluteString, forHTTPHeaderField: "Origin")
        if !config.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.addValue(config.cookieHeader, forHTTPHeaderField: "Cookie")
        }
        for (name, value) in config.additionalHeaders {
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty, !normalizedValue.isEmpty else { continue }
            guard !["host", "connection", "cookie", "origin"].contains(normalizedName.lowercased()) else { continue }
            request.setValue(normalizedValue, forHTTPHeaderField: normalizedName)
        }
        return request
    }

    public static func makeInitMessage(config: ASRConfiguration) throws -> Data {
        let params: [String: String] = [
            "app": "BloomCnVoiceInput",
            "audioType": "aac",
            "useAutoVAD": "true",
            "silence4StopInMilli": String(config.silence4StopInMilli),
            "silence4TimeoutInMilli": "500",
            "extraInfo": "",
            "needNormalization": "false",
            "needDenoise": "true",
            "deviceId": config.deviceId,
            "userId": config.userId,
            "client": "Android"
        ]
        return try encode(InitMessage(text: "[]", params: params))
    }

    public static func makeAudioMessage(packet: Data, packetIndex: Int) throws -> Data {
        try encode(AudioMessage(packet: packet.base64EncodedString(), packetIndex: packetIndex))
    }

    public static func makeStopMessage() throws -> Data {
        try encode(StopMessage())
    }

    public static func parseRecognitionMessage(_ message: String) throws -> RecognitionResult? {
        guard let root = try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              let tokensValue = root["tokens"] else {
            return nil
        }

        if let tokens = tokensValue as? String {
            let trimmedTokens = tokens.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTokens.isEmpty else { return nil }

            if let tokenData = trimmedTokens.data(using: .utf8),
               let result = try? JSONDecoder().decode(RecognitionResult.self, from: tokenData) {
                return result
            }

            if let tokenData = trimmedTokens.data(using: .utf8),
               let tokenObject = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any] {
                return makeRecognitionResult(from: tokenObject)
            }
            return RecognitionResult(text: trimmedTokens, msgType: (root["status"] as? Int) == 0 ? 1 : 0)
        }

        if let tokenObject = tokensValue as? [String: Any] {
            return makeRecognitionResult(from: tokenObject)
        }

        return nil
    }

    public static func tokensPreview(from message: String, limit: Int = 2_000) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              let tokensValue = root["tokens"] else {
            return "<no tokens>"
        }

        let raw: String
        if let tokens = tokensValue as? String {
            raw = tokens
        } else if JSONSerialization.isValidJSONObject(tokensValue),
                  let data = try? JSONSerialization.data(withJSONObject: tokensValue),
                  let text = String(data: data, encoding: .utf8) {
            raw = text
        } else {
            raw = String(describing: tokensValue)
        }

        return String(raw.prefix(limit))
    }

    private static func makeRecognitionResult(from tokenObject: [String: Any]) -> RecognitionResult? {
        let text = tokenObject["text"] as? String
            ?? tokenObject["content"] as? String
            ?? tokenObject["result"] as? String
        guard let text, !text.isEmpty else { return nil }

        let msgType = tokenObject["msgType"] as? Int
            ?? tokenObject["msg_type"] as? Int
            ?? 1
        return RecognitionResult(text: text, msgType: msgType)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
