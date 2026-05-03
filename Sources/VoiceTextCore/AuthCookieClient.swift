import Foundation

public enum AuthCookieClient {
    public enum AuthError: Error, LocalizedError {
        case missingAuthorization
        case invalidResponse
        case unauthorized

        public var errorDescription: String? {
            switch self {
            case .missingAuthorization:
                return "缺少 authorization header，无法自动获取 ASR Cookie"
            case .invalidResponse:
                return "Cookie 接口响应格式不正确"
            case .unauthorized:
                return "Cookie 接口鉴权失败"
            }
        }
    }

    private struct ResponseEnvelope: Decodable {
        let code: String
        let result: CookieResult?
    }

    private struct CookieResult: Decodable {
        let cookies: [CookieItem]
    }

    private struct CookieItem: Decodable {
        let name: String
        let value: String
    }

    public static func refreshCookies(for configuration: ASRConfiguration) async throws -> ASRConfiguration {
        let headers = headersWithAuthorization(from: configuration)
        guard headers.keys.contains(where: { $0.lowercased() == "authorization" }) else {
            throw AuthError.missingAuthorization
        }

        let role = configuration.role.rawValue
        let host = configuration.environment == .test ? "api.xiaoyuanjia.biz" : "api.xiaoyuanjia.com"
        guard let url = URL(string: "https://\(host)/bloom-atlas/android/\(role)/auth/fenbi-user-cookie") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        for (name, value) in headers {
            guard !["host", "connection", "cookie"].contains(name.lowercased()) else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 10
        sessionConfiguration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfiguration)

        VoiceTextLogger.log("Auth cookie refresh url=\(url.absoluteString) proxy=disabled")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        guard httpResponse.statusCode != 401 else {
            throw AuthError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard envelope.code == "0", let cookies = envelope.result?.cookies, !cookies.isEmpty else {
            throw AuthError.invalidResponse
        }

        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        let userId = cookies.first(where: { $0.name == "userid" })?.value ?? configuration.userId

        VoiceTextLogger.log("Auth cookie refresh success cookies=\(cookies.count) userId=\(userId)")
        return ASRConfiguration(
            environment: configuration.environment,
            userId: userId,
            role: configuration.role,
            deviceId: configuration.deviceId,
            cookieHeader: cookieHeader,
            phoneNumber: configuration.phoneNumber,
            password: configuration.password,
            authToken: configuration.authToken,
            additionalHeaders: headers,
            hotkeyKeyCode: configuration.hotkeyKeyCode,
            hotkeyModifiers: configuration.hotkeyModifiers,
            useAutoVAD: configuration.useAutoVAD,
            silence4StopInMilli: configuration.silence4StopInMilli,
            silence4TimeoutInMilli: configuration.silence4TimeoutInMilli,
            needNormalization: configuration.needNormalization,
            needDenoise: configuration.needDenoise
        )
    }

    private static func headersWithAuthorization(from configuration: ASRConfiguration) -> [String: String] {
        var headers = configuration.additionalHeaders
        if !headers.keys.contains(where: { $0.lowercased() == "authorization" }),
           !configuration.authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers["Authorization"] = "Bearer \(configuration.authToken)"
        }
        return headers
    }
}
