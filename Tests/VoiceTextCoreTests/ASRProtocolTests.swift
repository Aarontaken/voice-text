import XCTest
@testable import VoiceTextCore

final class ASRProtocolTests: XCTestCase {
    func testBuildsWebSocketURLForTestEnvironment() throws {
        let config = ASRConfiguration(
            environment: .test,
            userId: "12345",
            role: .student,
            deviceId: "mac-device",
            cookieHeader: "sid=abc; uid=123"
        )

        let url = try ASRProtocol.makeWebSocketURL(config: config, timestampMillis: 1_714_000_000_000)

        XCTAssertEqual(
            url.absoluteString,
            "wss://speech.yuanfudao.biz/apeman-cn-voice-input/asr?userId=12345&timestamp=1714000000000"
        )
    }

    func testBuildsInitMessageMatchingAndroidParameters() throws {
        let config = ASRConfiguration(
            environment: .production,
            userId: "u-1",
            role: .teacher,
            deviceId: "d-1",
            cookieHeader: "a=b"
        )

        let data = try ASRProtocol.makeInitMessage(config: config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = json?["params"] as? [String: String]

        XCTAssertEqual(json?["type"] as? Int, 1)
        XCTAssertEqual(json?["text"] as? String, "[]")
        XCTAssertEqual(params?["app"], "BloomCnVoiceInput")
        XCTAssertEqual(params?["audioType"], "aac")
        XCTAssertEqual(params?["useAutoVAD"], "true")
        XCTAssertEqual(params?["silence4StopInMilli"], "500")
        XCTAssertEqual(params?["silence4TimeoutInMilli"], "500")
        XCTAssertEqual(params?["needNormalization"], "false")
        XCTAssertEqual(params?["needDenoise"], "true")
        XCTAssertEqual(params?["deviceId"], "d-1")
        XCTAssertEqual(params?["userId"], "u-1")
        XCTAssertEqual(params?["client"], "Android")
    }

    func testBuildsInitMessageOnlyAllowsConfiguredCompletionPause() throws {
        let config = ASRConfiguration(
            environment: .production,
            userId: "u-1",
            role: .teacher,
            deviceId: "d-1",
            cookieHeader: "a=b",
            useAutoVAD: false,
            silence4StopInMilli: 900,
            silence4TimeoutInMilli: 1500,
            needNormalization: false,
            needDenoise: false
        )

        let data = try ASRProtocol.makeInitMessage(config: config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = json?["params"] as? [String: String]

        XCTAssertEqual(params?["useAutoVAD"], "true")
        XCTAssertEqual(params?["silence4StopInMilli"], "900")
        XCTAssertEqual(params?["silence4TimeoutInMilli"], "500")
        XCTAssertEqual(params?["needNormalization"], "false")
        XCTAssertEqual(params?["needDenoise"], "true")
    }

    func testBuildsBase64AudioPacketWithoutLineWrapping() throws {
        let data = try ASRProtocol.makeAudioMessage(packet: Data([0, 1, 2, 253, 254, 255]), packetIndex: 7)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? Int, 2)
        XCTAssertEqual(json?["packetIndex"] as? Int, 7)
        XCTAssertEqual(json?["packet"] as? String, "AAEC/f7/")
    }

    func testBuildsRequestWithAdditionalHeaders() throws {
        let config = ASRConfiguration(
            environment: .test,
            userId: "12345",
            role: .teacher,
            deviceId: "mac-device",
            cookieHeader: "",
            additionalHeaders: [
                "authorization": "Bearer token",
                "bloom-android-trace": "trace-id",
                "user-agent": "BloomTeacher/2.17.0"
            ]
        )

        let request = try ASRProtocol.makeURLRequest(config: config)

        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "bloom-android-trace"), "trace-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "user-agent"), "BloomTeacher/2.17.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connection"), "Upgrade")
    }

    func testParsesStreamingRecognitionToken() throws {
        let message = #"{"tokens":"{\"text\":\"你好\",\"silenceType\":0,\"audioDuration\":5440,\"msgType\":0,\"beginTime\":4960,\"endTime\":5440}","type":4}"#

        let result = try ASRProtocol.parseRecognitionMessage(message)

        XCTAssertEqual(result?.text, "你好")
        XCTAssertEqual(result?.msgType, 0)
        XCTAssertFalse(result?.isFinal ?? true)
    }

    func testParsesStopMessage() throws {
        let data = try ASRProtocol.makeStopMessage()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? Int, 3)
    }

    func testParsesFinalMessageWithoutType() throws {
        let message = #"{"score":0.0,"audioId":"audio.aac","tokens":"{\"text\":\"最终结果\",\"msgType\":1}","status":0}"#

        let result = try ASRProtocol.parseRecognitionMessage(message)

        XCTAssertEqual(result?.text, "最终结果")
        XCTAssertEqual(result?.msgType, 1)
        XCTAssertTrue(result?.isFinal ?? false)
    }
}
