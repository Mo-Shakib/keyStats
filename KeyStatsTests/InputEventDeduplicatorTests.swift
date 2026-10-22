import XCTest
@testable import KeyStatsHelperLogic

final class InputEventDeduplicatorTests: XCTestCase {
    func testMatchingSyntheticCopyIsCountedOnce() {
        var deduplicator = InputEventDeduplicator()
        XCTAssertFalse(deduplicator.shouldDrop(type: 22, detail: 1, sourcePID: 0, time: 10))
        XCTAssertTrue(deduplicator.shouldDrop(type: 22, detail: 1, sourcePID: 123, time: 10.02))
        XCTAssertTrue(deduplicator.shouldDrop(type: 22, detail: 1, sourcePID: 123, time: 10.04))
    }

    func testStandaloneOrUnrelatedSyntheticEventIsCounted() {
        var deduplicator = InputEventDeduplicator()
        XCTAssertFalse(deduplicator.shouldDrop(type: 10, detail: 4, sourcePID: 123, time: 10))
        XCTAssertFalse(deduplicator.shouldDrop(type: 10, detail: 4, sourcePID: 0, time: 11))
        XCTAssertFalse(deduplicator.shouldDrop(type: 10, detail: 5, sourcePID: 123, time: 11.01))
        XCTAssertFalse(deduplicator.shouldDrop(type: 10, detail: 4, sourcePID: 123, time: 11.1))
    }
}
