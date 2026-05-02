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
        return try JSONDecoder().decode(ASRConfiguration.self, from: data)
    }

    public func save(_ configuration: ASRConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("VoiceText", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
