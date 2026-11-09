import Foundation
import XCTest
@testable import CompanionCore

final class RemoteActivityGateTests: XCTestCase {
    func testTemporaryInactiveDoesNotMeanLockedOrPermitWork() {
        XCTAssertEqual(RemoteActivityGate.decision(state: .inactive,
            protectedDataAvailable: true, elapsed: .zero), .wait)
        XCTAssertEqual(RemoteActivityGate.decision(state: .inactive,
            protectedDataAvailable: true, elapsed: .milliseconds(4999)), .wait)
        XCTAssertEqual(RemoteActivityGate.decision(state: .inactive,
            protectedDataAvailable: true, elapsed: .seconds(5)), .inactiveTimedOut)
        XCTAssertEqual(RemoteActivityGate.decision(state: .active,
            protectedDataAvailable: true, elapsed: .seconds(5)), .proceed)
    }
    func testBackgroundNeverWaitsOrProceeds() {
        for available in [true, false] {
            XCTAssertEqual(RemoteActivityGate.decision(state: .background,
                protectedDataAvailable: available, elapsed: .zero), .background)
        }
    }
    func testProtectedDataMustBeActuallyAvailable() {
        for state in [RemoteActivityGate.State.active, .inactive] {
            XCTAssertEqual(RemoteActivityGate.decision(state: state,
                protectedDataAvailable: false, elapsed: .zero), .protectedDataUnavailable)
        }
    }
}
