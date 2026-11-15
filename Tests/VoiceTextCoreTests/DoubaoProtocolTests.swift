import XCTest
@testable import VoiceTextCore

final class DoubaoProtocolTests: XCTestCase {
    private let configuration = ASRConfiguration(
        apiKey: "test-api-key",
        resource: .seedASRDuration,
        language: "zh-CN",
        enableITN: true,
        enablePunc: true,
        enableDDC: true,
        endWindowSize: 900
    )

    func testURLRequestCarriesAuthAndResourceHeaders() throws {
        let request = try DoubaoProtocol.makeURLRequest(configuration: configuration, requestId: "request-1")

        XCTAssertEqual(request.url, DoubaoProtocol.endpoint(for: .oneShot))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "volc.seedasr.sauc.duration")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Request-Id"), "request-1")
    }

    func testRealtimeModeUsesAsyncEndpointAndTwoPass() throws {
        let realtime = ASRConfiguration(apiKey: "test-api-key", mode: .realtime)
        let request = try DoubaoProtocol.makeURLRequest(configuration: realtime, requestId: "request-1")
        XCTAssertEqual(request.url, DoubaoProtocol.endpoint(for: .realtime))
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/bigmodel_async") == true)

        let frame = try DoubaoProtocol.makeFullClientRequest(configuration: realtime, sequence: 1)
        let size = Int(uint32(frame, at: 8))
        let payload = try Gzip.decompress(frame.subdata(in: 12..<(12 + size)))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let requestOptions = try XCTUnwrap(root["request"] as? [String: Any])

        XCTAssertEqual(requestOptions["show_utterances"] as? Bool, true)
        XCTAssertEqual(requestOptions["enable_nonstream"] as? Bool, true)
        XCTAssertEqual(requestOptions["model_name"] as? String, "bigmodel")
    }

    func testURLRequestRejectsMissingAPIKey() {
        let empty = ASRConfiguration(apiKey: "  ")

        XCTAssertThrowsError(try DoubaoProtocol.makeURLRequest(configuration: empty, requestId: "request-1"))
    }

    func testFullClientRequestHeaderAndPayload() throws {
        let frame = try DoubaoProtocol.makeFullClientRequest(configuration: configuration, sequence: 1)

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x11, 0x11, 0x00])
        XCTAssertEqual(int32(frame, at: 4), 1)
        let size = Int(uint32(frame, at: 8))
        XCTAssertEqual(frame.count, 12 + size)

        let payload = try Gzip.decompress(frame.subdata(in: 12..<(12 + size)))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let audio = try XCTUnwrap(root["audio"] as? [String: Any])
        let request = try XCTUnwrap(root["request"] as? [String: Any])

        XCTAssertEqual(audio["format"] as? String, "pcm")
        XCTAssertEqual(audio["codec"] as? String, "raw")
        XCTAssertEqual(audio["rate"] as? Int, 16_000)
        XCTAssertEqual(audio["bits"] as? Int, 16)
        XCTAssertEqual(audio["channel"] as? Int, 1)
        XCTAssertEqual(audio["language"] as? String, "zh-CN")
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_ddc"] as? Bool, true)
        XCTAssertEqual(request["enable_nonstream"] as? Bool, nil)
        XCTAssertEqual(request["show_utterances"] as? Bool, false)
        XCTAssertEqual(request["end_window_size"] as? Int, 900)
    }

    func testAudioFrameUsesPositiveSequenceWhenNotLast() throws {
        let pcm = Data(repeating: 0x5A, count: 6_400)
        let frame = try DoubaoProtocol.makeAudioRequest(pcm: pcm, sequence: 2, isLast: false)

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x21, 0x11, 0x00])
        XCTAssertEqual(int32(frame, at: 4), 2)
        let size = Int(uint32(frame, at: 8))
        XCTAssertEqual(try Gzip.decompress(frame.subdata(in: 12..<(12 + size))), pcm)
    }

    func testAudioFrameUsesNegativeSequenceAndLastFlag() throws {
        let frame = try DoubaoProtocol.makeAudioRequest(
            pcm: Data(repeating: 0, count: 3_200),
            sequence: 4,
            isLast: true
        )

        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x23, 0x11, 0x00])
        XCTAssertEqual(int32(frame, at: 4), -4)
    }

    func testParsesFinalResponseWithTextAndLogId() throws {
        let payload: [String: Any] = [
            "audio_info": ["duration": 8_040],
            "result": [
                "text": "您好，我是您的 AI 助手。",
                "additions": ["log_id": "log-1"]
            ]
        ]
        let frame = try makeServerFrame(payload: payload, messageType: 9, flags: 0b0010)

        let response = try DoubaoProtocol.parseResponse(frame)

        XCTAssertTrue(response.isLastPackage)
        XCTAssertEqual(response.text, "您好，我是您的 AI 助手。")
        XCTAssertEqual(response.logId, "log-1")
        XCTAssertEqual(response.audioDurationMilliseconds, 8_040)
        XCTAssertEqual(response.code, 0)
    }

    func testParsesSequenceFlag() throws {
        let frame = try makeServerFrame(
            payload: ["result": ["text": "中间结果"]],
            messageType: 9,
            flags: 0b0001,
            sequence: 7
        )

        let response = try DoubaoProtocol.parseResponse(frame)

        XCTAssertEqual(response.payloadSequence, 7)
        XCTAssertFalse(response.isLastPackage)
        XCTAssertEqual(response.text, "中间结果")
    }

    func testParsesErrorResponse() throws {
        let frame = try makeServerFrame(
            payload: ["message": "invalid api key"],
            messageType: 15,
            flags: 0,
            code: 45_000_001
        )

        let response = try DoubaoProtocol.parseResponse(frame)

        XCTAssertEqual(response.code, 45_000_001)
        XCTAssertEqual(response.errorMessage, "invalid api key")
    }

    func testParsesDefiniteUtterances() throws {
        let payload: [String: Any] = [
            "audio_info": ["duration": 4_000],
            "result": [
                "text": "第一句。第二句。",
                "utterances": [
                    ["text": "第一句。", "definite": true, "start_time": 0, "end_time": 1_000],
                    ["text": "第二句。", "definite": false, "start_time": 1_000, "end_time": 2_000]
                ]
            ]
        ]
        let frame = try makeServerFrame(payload: payload, messageType: 9, flags: 0b0010)

        let response = try DoubaoProtocol.parseResponse(frame)

        XCTAssertEqual(response.text, "第一句。第二句。")
        XCTAssertEqual(response.utterances.count, 2)
        XCTAssertEqual(response.utterances[0].text, "第一句。")
        XCTAssertTrue(response.utterances[0].definite)
        XCTAssertFalse(response.utterances[1].definite)
        XCTAssertEqual(response.utterances[1].startTime, 1_000)
    }

    func testRejectsTruncatedFrame() {
        XCTAssertThrowsError(try DoubaoProtocol.parseResponse(Data([0x11, 0x92, 0x11])))
    }

    // MARK: - Helpers

    private func makeServerFrame(
        payload: [String: Any],
        messageType: Int,
        flags: Int,
        sequence: Int32? = nil,
        code: Int32? = nil
    ) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: payload)
        let compressed = try Gzip.compress(json)

        var frame = Data([
            0x11,
            UInt8((messageType << 4) | flags),
            0x11,
            0x00
        ])
        if let sequence {
            appendInt32(sequence, to: &frame)
        }
        if let code {
            appendInt32(code, to: &frame)
        }
        appendUInt32(UInt32(compressed.count), to: &frame)
        frame.append(compressed)
        return frame
    }

    private func appendInt32(_ value: Int32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func int32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(data, at: offset))
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data[offset..<(offset + 4)])
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }
}

extension DoubaoProtocolTests {
    func testIgnoresUnknownMessageType() throws {
        // 0xB0 = SERVER_ACK，客户端不消费，但不能因此判失败。
        let response = try DoubaoProtocol.parseResponse(Data([0x11, 0xB0, 0x00, 0x00]))

        XCTAssertEqual(response.messageType, 11)
        XCTAssertEqual(response.text, "")
        XCTAssertFalse(response.isLastPackage)
    }
}

extension DoubaoProtocolTests {
    func testParsesWrappedPayloadMessageShape() throws {
        let frame = try makeServerFrame(
            payload: ["payload_msg": ["result": ["text": "兼容旧形状"]]],
            messageType: 9,
            flags: 0b0010
        )

        let response = try DoubaoProtocol.parseResponse(frame)

        XCTAssertEqual(response.text, "兼容旧形状")
    }
}
