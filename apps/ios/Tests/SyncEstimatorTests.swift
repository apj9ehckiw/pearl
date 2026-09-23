import XCTest
@testable import PearlWallet

final class SyncEstimatorTests: XCTestCase {
    func testEstimateUsesWalletScanProgressAndExpiresWhenStalled() {
        var estimate = SyncEstimator()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(estimate.update(walletHeight: 100, peerHeight: 200, synced: false, now: start))
        XCTAssertEqual(estimate.update(walletHeight: 110, peerHeight: 200, synced: false,
                                       now: start.addingTimeInterval(10)) ?? -1, 90, accuracy: 0.01)
        XCTAssertNil(estimate.update(walletHeight: 110, peerHeight: 200, synced: false,
                                     now: start.addingTimeInterval(101)))
        XCTAssertNil(estimate.update(walletHeight: 200, peerHeight: 200, synced: true,
                                     now: start.addingTimeInterval(102)))
    }
}
