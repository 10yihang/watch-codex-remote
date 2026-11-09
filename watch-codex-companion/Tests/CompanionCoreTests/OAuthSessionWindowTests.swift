import Foundation
import XCTest
@testable import CompanionCore

final class OAuthSessionWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    func testDefaultWindowAllowsMFAAppSwitchWithoutRenewal() throws {
        let window = try OAuthSessionWindow(startedAt: start)
        XCTAssertNoThrow(try window.validate(now: start.addingTimeInterval(180)))
        XCTAssertNoThrow(try window.validate(now: start.addingTimeInterval(599.9)))
        XCTAssertEqual(window.expiresAt, start.addingTimeInterval(600))
        XCTAssertThrowsError(try window.validate(now: start.addingTimeInterval(600)))
        XCTAssertThrowsError(try window.validate(now: start.addingTimeInterval(1200)))
    }
    func testWindowBoundsAndFractionalTimeout() throws {
        for timeout in [Duration.zero, .seconds(-1), .seconds(601)] {
            XCTAssertThrowsError(try OAuthSessionWindow(startedAt: start, timeout: timeout))
        }
        let window = try OAuthSessionWindow(startedAt: start, timeout: .milliseconds(1500))
        XCTAssertNoThrow(try window.validate(now: start.addingTimeInterval(1.49)))
        XCTAssertThrowsError(try window.validate(now: start.addingTimeInterval(1.5)))
    }
}
