import XCTest
@testable import VoiceTextCore

final class SettingsStoreTests: XCTestCase {
    func testSavesAndLoadsConfigurationFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let config = ASRConfiguration(
            environment: .test,
            userId: "user-1",
            role: .student,
            deviceId: "device-1",
            cookieHeader: "sid=abc",
            additionalHeaders: ["authorization": "Bearer token"]
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
    }

    func testDefaultConfigurationUsesStableMacDeviceId() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(fileURL: directory.appendingPathComponent("missing.json"))
        let config = try store.load()

        XCTAssertEqual(config.environment, .test)
        XCTAssertEqual(config.role, .student)
        XCTAssertFalse(config.deviceId.isEmpty)
    }
}
