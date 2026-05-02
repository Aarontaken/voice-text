import XCTest
@testable import VoiceTextCore

final class AudioEncodingTests: XCTestCase {
    func testBuildsADTSHeaderForAACLC16kMonoPacket() {
        let header = ADTSHeader.makeHeader(payloadLength: 20, sampleRate: 16_000, channelCount: 1)

        XCTAssertEqual(header.count, 7)
        XCTAssertEqual(header[0], 0xFF)
        XCTAssertEqual(header[1], 0xF1)
        XCTAssertEqual(header[2], 0x60)
        XCTAssertEqual(header[3], 0x40)
        XCTAssertEqual(header[4], 0x03)
        XCTAssertEqual(header[5], 0x7F)
        XCTAssertEqual(header[6], 0xFC)
    }

    func testRejectsUnsupportedSampleRateForADTSHeader() {
        XCTAssertThrowsError(
            try ADTSHeader.makeValidatedHeader(payloadLength: 10, sampleRate: 15_000, channelCount: 1)
        )
    }
}
