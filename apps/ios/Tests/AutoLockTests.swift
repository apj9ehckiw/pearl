import XCTest
@testable import PearlWallet

final class AutoLockTests: XCTestCase {
    func testIdleThresholdIncludesBackgroundTime() {
        let lastActivity = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(AutoLockPolicy.shouldLock(since: lastActivity,
            now: lastActivity.addingTimeInterval(299), configuredMinutes: 5))
        XCTAssertTrue(AutoLockPolicy.shouldLock(since: lastActivity,
            now: lastActivity.addingTimeInterval(300), configuredMinutes: 5))
        XCTAssertTrue(AutoLockPolicy.shouldLock(since: lastActivity,
            now: lastActivity.addingTimeInterval(60), configuredMinutes: 1))
    }
}
