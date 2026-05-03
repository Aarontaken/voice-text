import XCTest
@testable import VoiceTextCore

final class ControlKeyTapTrackerTests: XCTestCase {
    func testSingleShortTapDoesNotTriggerDoubleTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        let didDoubleTap = tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0)

        XCTAssertFalse(didDoubleTap)
    }

    func testTwoShortTapsWithinIntervalTriggerDoubleTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.07, releaseTime: 10.0))
        XCTAssertTrue(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.25))
    }

    func testSecondTapAfterIntervalStartsNewSequence() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.07, releaseTime: 10.0))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.5))
        XCTAssertTrue(tracker.recordTap(pressDuration: 0.06, releaseTime: 10.75))
    }

    func testLongPressDoesNotCountAsTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.4, releaseTime: 10.2))
        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.4))
    }

    func testResetClearsPendingTap() {
        var tracker = ControlKeyTapTracker(doubleTapInterval: 0.35, maxTapDuration: 0.22)

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.0))
        tracker.reset()

        XCTAssertFalse(tracker.recordTap(pressDuration: 0.08, releaseTime: 10.2))
    }
}
