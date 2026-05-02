import XCTest
@testable import VoiceTextCore

final class RecognitionBufferTests: XCTestCase {
    func testDoesNotRepeatFinalFullTextAfterStreamingTextWasInserted() {
        var buffer = RecognitionBuffer()

        XCTAssertEqual(buffer.consume(RecognitionResult(text: "你好", msgType: 0)), "你好")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "你好世界", msgType: 0)), "世界")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "你好世界", msgType: 1)), "")
    }

    func testAllowsNewTextAfterFinalResult() {
        var buffer = RecognitionBuffer()

        XCTAssertEqual(buffer.consume(RecognitionResult(text: "第一句", msgType: 0)), "第一句")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "第一句", msgType: 1)), "")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "第二句", msgType: 0)), "第二句")
    }

    func testDoesNotPoisonStateWhenServerRevisesFullText() {
        var buffer = RecognitionBuffer()

        XCTAssertEqual(buffer.consume(RecognitionResult(text: "abcdef", msgType: 0)), "abcdef")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "abcxefg", msgType: 0)), "xefg")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "abcxefghi", msgType: 0)), "hi")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "abcxefghi", msgType: 1)), "")
    }

    func testKeepsIncrementalPacketsWhenTheyAreNotFullText() {
        var buffer = RecognitionBuffer()

        XCTAssertEqual(buffer.consume(RecognitionResult(text: "你", msgType: 0)), "你")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "好", msgType: 0)), "好")
        XCTAssertEqual(buffer.consume(RecognitionResult(text: "了", msgType: 1)), "了")
    }
}
