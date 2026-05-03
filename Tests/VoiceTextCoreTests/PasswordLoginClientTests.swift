import XCTest
@testable import VoiceTextCore

final class PasswordLoginClientTests: XCTestCase {
    func testBuildsTeacherPasswordLoginRequest() throws {
        let request = try PasswordLoginClient.makeLoginRequest(
            environment: .test,
            phone: "13800138000",
            password: "secret"
        )

        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.xiaoyuanjia.biz")
        XCTAssertEqual(request.url?.path, "/bloom-atlas/android/teacher/auth/password-login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "BloomTeacher/2.17.0 (Mac; VoiceText)")

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(json?["phone"], "13800138000")
        XCTAssertEqual(json?["password"], "secret")
    }

    func testParsesPasswordLoginToken() throws {
        let data = Data(#"{"code":"0","result":{"token":"abc.def.ghi"}}"#.utf8)

        let token = try PasswordLoginClient.parseToken(from: data)

        XCTAssertEqual(token, "abc.def.ghi")
    }

    func testConfigurationByApplyingLoginPreservesAdvancedASRSettings() {
        let config = ASRConfiguration(
            environment: .test,
            userId: "u-1",
            role: .student,
            deviceId: "d-1",
            cookieHeader: "sid=abc",
            useAutoVAD: false,
            silence4StopInMilli: 700,
            silence4TimeoutInMilli: 1400,
            needNormalization: false,
            needDenoise: false
        )

        let updated = PasswordLoginClient.configurationByApplyingLogin(
            token: "token-1",
            phone: "13800000000",
            password: "secret",
            to: config
        )

        XCTAssertEqual(updated.useAutoVAD, false)
        XCTAssertEqual(updated.silence4StopInMilli, 700)
        XCTAssertEqual(updated.silence4TimeoutInMilli, 1400)
        XCTAssertEqual(updated.needNormalization, false)
        XCTAssertEqual(updated.needDenoise, false)
    }
}
