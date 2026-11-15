import XCTest
@testable import VoiceTextCore

final class MicrophoneAvailabilityTests: XCTestCase {
    func testClosedLidWithBuiltInMicrophoneIsReported() {
        XCTAssertEqual(
            MicrophoneAvailability.issue(lidClosed: true, defaultInputIsBuiltIn: true),
            .lidClosedWithBuiltInMicrophone
        )
    }

    func testClosedLidWithExternalMicrophoneIsAllowed() {
        XCTAssertNil(MicrophoneAvailability.issue(lidClosed: true, defaultInputIsBuiltIn: false))
    }

    func testOpenLidWithBuiltInMicrophoneIsAllowed() {
        XCTAssertNil(MicrophoneAvailability.issue(lidClosed: false, defaultInputIsBuiltIn: true))
    }

    func testIssueTextsAreActionable() {
        let issue = MicrophoneAvailability.Issue.lidClosedWithBuiltInMicrophone
        XCTAssertFalse(issue.title.isEmpty)
        XCTAssertFalse(issue.statusText.isEmpty)
        XCTAssertTrue(issue.detail.contains("外置麦克风"))
        XCTAssertTrue(issue.detail.contains("打开机盖"))
        // 提示要短：一行能读完，不解释原理。
        XCTAssertLessThanOrEqual(issue.detail.count, 40)
    }
}
