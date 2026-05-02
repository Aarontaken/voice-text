import Foundation

public enum PasswordLoginClient {
    public enum LoginError: Error, LocalizedError {
        case missingCredentials
        case invalidResponse
        case unauthorized(String)

        public var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "请先填写手机号和密码"
            case .invalidResponse:
                return "登录接口响应格式不正确"
            case let .unauthorized(message):
                return message.isEmpty ? "手机号或密码错误" : message
            }
        }
    }

    private struct LoginRequestBody: Encodable {
        let phone: String
        let password: String
    }

    public static func login(
        environment: ASRConfiguration.Environment,
        phone: String,
        password: String
    ) async throws -> String {
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPhone.isEmpty, !normalizedPassword.isEmpty else {
            throw LoginError.missingCredentials
        }

        let request = try makeLoginRequest(
            environment: environment,
            phone: normalizedPhone,
            password: normalizedPassword
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 10
        sessionConfiguration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfiguration)

        VoiceTextLogger.log("Password login request host=\(request.url?.host ?? "") proxy=disabled")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoginError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LoginError.unauthorized("登录失败，HTTP \(httpResponse.statusCode)")
        }
        let token = try parseToken(from: data)
        VoiceTextLogger.log("Password login success tokenLength=\(token.count)")
        return token
    }

    public static func makeLoginRequest(
        environment: ASRConfiguration.Environment,
        phone: String,
        password: String
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = environment == .test ? "api.xiaoyuanjia.biz" : "api.xiaoyuanjia.com"
        components.path = "/bloom-atlas/android/teacher/auth/password-login"
        components.queryItems = [
            URLQueryItem(name: "productId", value: "55000003"),
            URLQueryItem(name: "platform", value: "android16"),
            URLQueryItem(name: "version", value: "2.17.0"),
            URLQueryItem(name: "_version", value: "2.17.0")
        ]
        guard let url = components.url else {
            throw LoginError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BloomTeacher/2.17.0 (Mac; VoiceText)", forHTTPHeaderField: "User-Agent")
        request.setValue(makeTraceId(), forHTTPHeaderField: "Bloom-Android-Trace")
        request.httpBody = try JSONEncoder().encode(LoginRequestBody(phone: phone, password: password))
        return request
    }

    public static func parseToken(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoginError.invalidResponse
        }

        let codeText = String(describing: root["code"] ?? "0")
        if codeText != "0" {
            throw LoginError.unauthorized((root["message"] as? String) ?? "")
        }

        guard let result = root["result"] as? [String: Any],
              let token = result["token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LoginError.invalidResponse
        }
        return token
    }

    public static func configurationByApplyingLogin(
        token: String,
        phone: String,
        password: String,
        to configuration: ASRConfiguration
    ) -> ASRConfiguration {
        var headers = configuration.additionalHeaders
        headers["Authorization"] = "Bearer \(token)"
        return ASRConfiguration(
            environment: configuration.environment,
            userId: configuration.userId,
            role: .teacher,
            deviceId: configuration.deviceId,
            cookieHeader: configuration.cookieHeader,
            phoneNumber: phone,
            password: password,
            authToken: token,
            additionalHeaders: headers,
            hotkeyKeyCode: configuration.hotkeyKeyCode,
            hotkeyModifiers: configuration.hotkeyModifiers
        )
    }

    private static func makeTraceId() -> String {
        "\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
    }
}
