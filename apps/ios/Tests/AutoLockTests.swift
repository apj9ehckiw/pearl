import XCTest
@testable import PearlWallet

final class AutoLockTests: XCTestCase {
    func testOnlyBackgroundDurationCountsTowardLock() {
        let enteredBackground = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(AutoLockPolicy.shouldLock(backgroundEnteredAt: enteredBackground,
            now: enteredBackground.addingTimeInterval(299), configuredMinutes: 5))
        XCTAssertTrue(AutoLockPolicy.shouldLock(backgroundEnteredAt: enteredBackground,
            now: enteredBackground.addingTimeInterval(300), configuredMinutes: 5))
        XCTAssertTrue(AutoLockPolicy.shouldLock(backgroundEnteredAt: enteredBackground,
            now: enteredBackground.addingTimeInterval(60), configuredMinutes: 1))
    }
}
