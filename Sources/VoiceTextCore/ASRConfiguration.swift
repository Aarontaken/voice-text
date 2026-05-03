import Foundation

public struct ASRConfiguration: Codable, Equatable, Sendable {
    public enum Environment: String, Codable, CaseIterable, Sendable {
        case test
        case production

        var speechHost: String {
            switch self {
            case .test:
                return "speech.yuanfudao.biz"
            case .production:
                return "speech.yuanfudao.com"
            }
        }
    }

    public enum Role: String, Codable, CaseIterable, Sendable {
        case student
        case teacher
    }

    public var environment: Environment
    public var userId: String
    public var role: Role
    public var deviceId: String
    public var cookieHeader: String
    public var phoneNumber: String
    public var password: String
    public var authToken: String
    public var additionalHeaders: [String: String]
    public var hotkeyKeyCode: UInt32
    public var hotkeyModifiers: UInt32
    public var useAutoVAD: Bool
    public var silence4StopInMilli: Int
    public var silence4TimeoutInMilli: Int
    public var needNormalization: Bool
    public var needDenoise: Bool

    private enum CodingKeys: String, CodingKey {
        case environment
        case userId
        case role
        case deviceId
        case cookieHeader
        case phoneNumber
        case password
        case authToken
        case additionalHeaders
        case hotkeyKeyCode
        case hotkeyModifiers
        case useAutoVAD
        case silence4StopInMilli
        case silence4TimeoutInMilli
        case needNormalization
        case needDenoise
    }

    public init(
        environment: Environment,
        userId: String,
        role: Role,
        deviceId: String,
        cookieHeader: String,
        phoneNumber: String = "",
        password: String = "",
        authToken: String = "",
        additionalHeaders: [String: String] = [:],
        hotkeyKeyCode: UInt32 = 49,
        hotkeyModifiers: UInt32 = 1 << 11,
        useAutoVAD: Bool = true,
        silence4StopInMilli: Int = 500,
        silence4TimeoutInMilli: Int = 500,
        needNormalization: Bool = false,
        needDenoise: Bool = true
    ) {
        self.environment = environment
        self.userId = userId
        self.role = role
        self.deviceId = deviceId
        self.cookieHeader = cookieHeader
        self.phoneNumber = phoneNumber
        self.password = password
        self.authToken = authToken
        self.additionalHeaders = additionalHeaders
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.useAutoVAD = useAutoVAD
        self.silence4StopInMilli = silence4StopInMilli
        self.silence4TimeoutInMilli = silence4TimeoutInMilli
        self.needNormalization = needNormalization
        self.needDenoise = needDenoise
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environment = try container.decode(Environment.self, forKey: .environment)
        userId = try container.decode(String.self, forKey: .userId)
        role = try container.decode(Role.self, forKey: .role)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        cookieHeader = try container.decodeIfPresent(String.self, forKey: .cookieHeader) ?? ""
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        additionalHeaders = try container.decodeIfPresent([String: String].self, forKey: .additionalHeaders) ?? [:]
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? 49
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? (1 << 11)
        useAutoVAD = try container.decodeIfPresent(Bool.self, forKey: .useAutoVAD) ?? true
        silence4StopInMilli = try container.decodeIfPresent(Int.self, forKey: .silence4StopInMilli) ?? 500
        silence4TimeoutInMilli = try container.decodeIfPresent(Int.self, forKey: .silence4TimeoutInMilli) ?? 500
        needNormalization = try container.decodeIfPresent(Bool.self, forKey: .needNormalization) ?? false
        needDenoise = try container.decodeIfPresent(Bool.self, forKey: .needDenoise) ?? true
    }

    public static func defaultConfiguration() -> ASRConfiguration {
        ASRConfiguration(
            environment: .test,
            userId: "",
            role: .student,
            deviceId: "mac-\(Host.current().localizedName ?? UUID().uuidString)",
            cookieHeader: ""
        )
    }
}
