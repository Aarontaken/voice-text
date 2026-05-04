import XCTest
@testable import VoiceTextCore

final class HoldControlExtraModifierDetectorTests: XCTestCase {
    func testControlAloneDoesNotCancel() {
        let controlOnly = UInt64(1 << 18)
        XCTAssertFalse(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: controlOnly
            )
        )
    }

    func testControlPlusShiftCancels() {
        let control = UInt64(1 << 18)
        let shift = UInt64(1 << 17)
        XCTAssertTrue(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: control | shift
            )
        )
    }

    func testShiftAloneWithoutControlDoesNotCancel() {
        let shiftOnly = UInt64(1 << 17)
        XCTAssertFalse(
            HoldControlExtraModifierDetector.shouldCancelHoldBecauseAddedModifiers(
                deviceIndependentRaw: shiftOnly
            )
        )
    }
}
