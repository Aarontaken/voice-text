import XCTest
@testable import VoiceTextCore

final class GzipTests: XCTestCase {
    func testRoundTripPreservesUTF8Content() throws {
        let text = "豆包语音识别 hello 123"
        let source = Data(text.utf8)
        let compressed = try Gzip.compress(source)

        XCTAssertEqual(compressed.prefix(2), Data([0x1F, 0x8B]))
        XCTAssertEqual(try Gzip.decompress(compressed), source)
    }

    func testRoundTripLargeBinaryPayload() throws {
        var source = Data(repeating: 0, count: 6_400)
        for index in stride(from: 0, to: source.count, by: 3) {
            source[index] = UInt8(truncatingIfNeeded: index)
        }

        let compressed = try Gzip.compress(source)
        XCTAssertLessThan(compressed.count, source.count)
        XCTAssertEqual(try Gzip.decompress(compressed), source)
    }

    func testDecompressesStandardGzipFixture() throws {
        // python3: gzip.compress("豆包语音识别 hello".encode(), mtime=0)
        let base64 = "H4sIAAAAAAAC/3uxse1pT+uL9Wtfzt/8Yn3b047VChmpOTn5AMkgL5IYAAAA"
        let fixture = try XCTUnwrap(Data(base64Encoded: base64))

        let decompressed = try Gzip.decompress(fixture)

        XCTAssertEqual(String(data: decompressed, encoding: .utf8), "豆包语音识别 hello")
    }

    func testTrailerCarriesISizeAndCRC() throws {
        let source = Data(repeating: 0x41, count: 12_345)
        let compressed = try Gzip.compress(source)

        let trailer = [UInt8](compressed.suffix(8))
        let expectedCRC = Gzip.crc32(source).littleEndian
        let crc = UInt32(trailer[0])
            | (UInt32(trailer[1]) << 8)
            | (UInt32(trailer[2]) << 16)
            | (UInt32(trailer[3]) << 24)
        let isize = UInt32(trailer[4])
            | (UInt32(trailer[5]) << 8)
            | (UInt32(trailer[6]) << 16)
            | (UInt32(trailer[7]) << 24)

        XCTAssertEqual(crc, expectedCRC)
        XCTAssertEqual(isize, UInt32(source.count))
    }

    func testRejectsInvalidHeader() {
        XCTAssertThrowsError(try Gzip.decompress(Data(repeating: 0, count: 32)))
    }
}
