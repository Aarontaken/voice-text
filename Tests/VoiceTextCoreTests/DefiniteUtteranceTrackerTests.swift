import XCTest
@testable import VoiceTextCore

final class DefiniteUtteranceTrackerTests: XCTestCase {
    func testEmitsOnlyNewlyDefiniteUtterances() {
        var tracker = DefiniteUtteranceTracker()
        let first = DoubaoUtterance(text: "第一句。", definite: true, startTime: 0, endTime: 1_000)
        let secondInterim = DoubaoUtterance(text: "第二句", definite: false, startTime: 1_000, endTime: 2_000)

        XCTAssertEqual(tracker.takeNewDefinite([first, secondInterim]), ["第一句。"])
        XCTAssertEqual(tracker.takeNewDefinite([first, secondInterim]), [])

        let secondFinal = DoubaoUtterance(text: "第二句。", definite: true, startTime: 1_000, endTime: 2_000)
        XCTAssertEqual(tracker.takeNewDefinite([first, secondFinal]), ["第二句。"])
        XCTAssertEqual(tracker.takeNewDefinite([first, secondFinal]), [])
    }

    func testZeroTimestampsFallBackToArrayIndex() {
        var tracker = DefiniteUtteranceTracker()
        let utterance = DoubaoUtterance(text: "没有时间戳。", definite: true, startTime: 0, endTime: 0)

        XCTAssertEqual(tracker.takeNewDefinite([utterance]), ["没有时间戳。"])
        XCTAssertEqual(tracker.takeNewDefinite([utterance]), [])
    }

    func testResetAllowsReuseAcrossSessions() {
        var tracker = DefiniteUtteranceTracker()
        let utterance = DoubaoUtterance(text: "重复。", definite: true, startTime: 0, endTime: 500)

        XCTAssertEqual(tracker.takeNewDefinite([utterance]), ["重复。"])
        tracker.reset()
        XCTAssertEqual(tracker.takeNewDefinite([utterance]), ["重复。"])
    }

    func testIgnoresEmptyText() {
        var tracker = DefiniteUtteranceTracker()
        let utterance = DoubaoUtterance(text: "  ", definite: true, startTime: 0, endTime: 100)

        XCTAssertEqual(tracker.takeNewDefinite([utterance]), [])
    }
}
