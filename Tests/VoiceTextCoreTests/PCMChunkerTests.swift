import XCTest
@testable import VoiceTextCore

final class PCMChunkerTests: XCTestCase {
    func testHoldsBackOneChunk() {
        var chunker = PCMChunker(chunkSize: 6_400)

        XCTAssertTrue(chunker.append(Data(repeating: 1, count: 6_400)).isEmpty)

        let chunks = chunker.append(Data(repeating: 2, count: 6_400))
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], Data(repeating: 1, count: 6_400))
        XCTAssertEqual(chunker.pendingByteCount, 6_400)

        XCTAssertTrue(chunker.append(Data(repeating: 3, count: 2)).isEmpty)
        XCTAssertEqual(chunker.finish().map(\.count), [6_402])
    }

    func testFinishSplitsRemainderAndKeepsLastShort() {
        var chunker = PCMChunker(chunkSize: 6_400)
        XCTAssertTrue(chunker.append(Data(repeating: 7, count: 10_000)).isEmpty)

        let remaining = chunker.finish()

        XCTAssertEqual(remaining.map(\.count), [6_400, 3_600])
        XCTAssertEqual(chunker.pendingByteCount, 0)
    }

    func testFinishReturnsSingleShortChunkForShortUtterance() {
        var chunker = PCMChunker(chunkSize: 6_400)
        XCTAssertTrue(chunker.append(Data(repeating: 9, count: 2_000)).isEmpty)

        XCTAssertEqual(chunker.finish().map(\.count), [2_000])
        XCTAssertTrue(chunker.finish().isEmpty)
    }

    func testExactMultipleSendsHeldChunkOnFinish() {
        var chunker = PCMChunker(chunkSize: 6_400)
        let chunks = chunker.append(Data(repeating: 5, count: 12_800))

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunker.pendingByteCount, 6_400)
        XCTAssertEqual(chunker.finish().map(\.count), [6_400])
    }

    func testLargeAppendEmitsAllButOneChunk() {
        var chunker = PCMChunker(chunkSize: 6_400)
        let chunks = chunker.append(Data(repeating: 4, count: 6_400 * 5))

        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunker.pendingByteCount, 6_400)
    }

    func testNoAudioProducesNoFrames() {
        var chunker = PCMChunker(chunkSize: 6_400)
        XCTAssertTrue(chunker.finish().isEmpty)
    }
}
