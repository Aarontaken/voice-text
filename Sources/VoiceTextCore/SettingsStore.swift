import Foundation

public final class SettingsStore {
    public let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> ASRConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let config = ASRConfiguration.defaultConfiguration()
            try save(config)
            return config
        }

        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(ASRConfiguration.self, from: data)

        // 旧版 settings.json 里还留着手机号/密码/token/cookie，加载时顺手重写，
        // 把已经废弃的小猿账号字段从磁盘上清掉。
        if Self.containsLegacyKeys(in: data) {
            try? save(configuration)
        }
        return configuration
    }

    private static let legacyKeys: Set<String> = [
        "environment",
        "userId",
        "role",
        "deviceId",
        "cookieHeader",
        "phoneNumber",
        "password",
        "authToken",
        "silence4StopInMilli",
        "useAutoVAD"
    ]

    private static func containsLegacyKeys(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return !legacyKeys.isDisjoint(with: root.keys)
    }

    public func save(_ configuration: ASRConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
        // 配置里有 API Key，尽量只让当前用户可读。
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("VoiceText", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
