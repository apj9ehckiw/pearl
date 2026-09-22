import XCTest
@testable import PearlWallet

final class PearlAmountTests: XCTestCase {
    func testExactAtomicAmounts() {
        XCTAssertEqual(PearlAmount.grains("0.00000001"), 1)
        XCTAssertEqual(PearlAmount.grains("1.23456789"), 123456789)
        XCTAssertEqual(PearlAmount.grains("21000000000"), 2100000000000000000)
        XCTAssertEqual(PearlAmount.display(123456789), "1.23456789")
    }
    func testRejectUnsafeInputs() {
        for value in ["0", "-1", "1e8", "0.000000001", "1,000", "nan", "21000000001", "", "1."] {
            XCTAssertNil(PearlAmount.grains(value), value)
        }
    }
}
