import XCTest
@testable import VoiceTextCore

final class SettingsStoreTests: XCTestCase {
    private func makeStore() throws -> (SettingsStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (SettingsStore(fileURL: directory.appendingPathComponent("settings.json")), directory)
    }

    func testSavesAndLoadsConfigurationFromDisk() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = ASRConfiguration(
            apiKey: "key-1",
            mode: .realtime,
            resource: .seedASRConcurrent,
            language: "en-US",
            enableITN: false,
            enablePunc: true,
            enableDDC: true,
            showUtterances: true,
            endWindowSize: 1_200,
            forceToSpeechTime: 500
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
    }

    func testMissingFileCreatesDefaultConfiguration() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = try store.load()

        XCTAssertEqual(config, ASRConfiguration.defaultConfiguration())
        XCTAssertFalse(config.hasAPIKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testDefaultConfigurationUsesDoubaoDefaults() {
        let config = ASRConfiguration.defaultConfiguration()

        XCTAssertEqual(config.mode, .oneShot)
        XCTAssertEqual(config.resource, .seedASRDuration)
        XCTAssertEqual(config.endWindowSize, 800)
        XCTAssertEqual(config.forceToSpeechTime, 1_000)
        XCTAssertTrue(config.enableITN)
        XCTAssertTrue(config.enablePunc)
        XCTAssertFalse(config.enableDDC)
        XCTAssertFalse(config.hasAPIKey)
    }

    func testDecodesLegacyXiaoyuanjiaConfigurationAsDefaults() throws {
        let json = #"""
        {
          "environment" : "test",
          "userId" : "user-1",
          "role" : "teacher",
          "deviceId" : "device-1",
          "cookieHeader" : "sid=abc",
          "authToken" : "bearer-token",
          "silence4StopInMilli" : 500
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(ASRConfiguration.self, from: json)

        XCTAssertFalse(config.hasAPIKey)
        XCTAssertEqual(config.mode, .oneShot)
        XCTAssertEqual(config.resource, .seedASRDuration)
        XCTAssertEqual(config.endWindowSize, 800)
        XCTAssertEqual(config.language, "")
    }

    func testDecodesPartialConfigurationWithDefaults() throws {
        let json = #"""
        {
          "apiKey" : "key-1",
          "endWindowSize" : 1500
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(ASRConfiguration.self, from: json)

        XCTAssertEqual(config.apiKey, "key-1")
        XCTAssertEqual(config.endWindowSize, 1_500)
        XCTAssertEqual(config.resource, .seedASRDuration)
        XCTAssertTrue(config.enableITN)
    }
}

extension SettingsStoreTests {
    func testLoadRewritesLegacyCredentialsOutOfDisk() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = #"""
        {
          "environment" : "test",
          "password" : "super-secret",
          "cookieHeader" : "sid=abc",
          "authToken" : "bearer-token"
        }
        """#
        try Data(legacy.utf8).write(to: store.fileURL)

        let config = try store.load()
        let rewritten = try String(contentsOf: store.fileURL, encoding: .utf8)

        XCTAssertFalse(rewritten.contains("super-secret"))
        XCTAssertFalse(rewritten.contains("cookieHeader"))
        XCTAssertFalse(rewritten.contains("authToken"))
        XCTAssertEqual(config, ASRConfiguration.defaultConfiguration())
    }
}
