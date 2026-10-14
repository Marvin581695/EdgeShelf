import XCTest
@testable import EdgeShelf

final class CopySequenceTests: XCTestCase {
    func testDoubleCopyFiresOnce() {
        var sequence = CopySequence()
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 10, required: 2, interval: 0.65))
        XCTAssertTrue(sequence.press(isCommandC: true, isRepeat: false, time: 10.3, required: 2, interval: 0.65))
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 10.4, required: 2, interval: 0.65))
    }

    func testCustomCountAndTimeout() {
        var sequence = CopySequence()
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 10, required: 3, interval: 0.5))
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 11, required: 3, interval: 0.5))
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 11.2, required: 3, interval: 0.5))
        XCTAssertTrue(sequence.press(isCommandC: true, isRepeat: false, time: 11.4, required: 3, interval: 0.5))
    }

    func testAutorepeatDoesNotCountAndOtherKeyResets() {
        var sequence = CopySequence()
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 1, required: 2, interval: 0.65))
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: true, time: 1.1, required: 2, interval: 0.65))
        XCTAssertFalse(sequence.press(isCommandC: false, isRepeat: false, time: 1.2, required: 2, interval: 0.65))
        XCTAssertFalse(sequence.press(isCommandC: true, isRepeat: false, time: 1.3, required: 2, interval: 0.65))
        XCTAssertTrue(sequence.press(isCommandC: true, isRepeat: false, time: 1.4, required: 2, interval: 0.65))
    }
}
