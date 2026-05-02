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
}
