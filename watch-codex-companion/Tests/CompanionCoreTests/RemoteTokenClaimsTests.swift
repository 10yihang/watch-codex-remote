import Foundation
import XCTest
@testable import CompanionCore

// Unsigned, synthetic fixtures only. No credentials or network operations.
final class RemoteTokenClaimsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private func fixture(_ changes: [String: Any] = [:]) throws -> String {
        var body: [String: Any] = [
            "exp": 1_900_000_600, "iat": 1_899_999_990,
            "pwd_auth_time": 1_899_999_990_000 as Int64,
            "client_id": "public-client", "scope": RemoteTokenClaims.stepUpScope,
            "https://api.openai.com/auth": ["chatgpt_account_id": "account", "chatgpt_account_user_id": "user", "organizations": [], "user_id": "token-user"] as [String: Any]
        ]
        body.merge(changes) { _, value in value }
        let encoded = try JSONSerialization.data(withJSONObject: body).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).c3ludGhldGlj"
    }
    private func validate(_ token: String) throws {
        try RemoteTokenClaims.validateStepUp(rawValue: token, accountID: "account", accountUserID: "user", clientID: "public-client", now: now)
    }
    func testOrdinaryClaimsAreRoutingOnly() throws {
        let result = try RemoteTokenClaims.parseOrdinary(accessToken: fixture(), expectedClientID: "public-client", now: now)
        XCTAssertEqual(result.accountID, "account")
        XCTAssertEqual(result.accountUserID, "user")
        XCTAssertEqual(result.tokenUserID, "token-user")
        // Deliberately unsigned fixture: local decoder is NOT JWT verification.
        XCTAssertNoThrow(try validate(fixture()))
    }
    func testStepUpRejectsStaleFutureExpiredWrongScopeAndClient() throws {
        let cases: [[String: Any]] = [
            ["iat": 1_899_999_699], ["iat": 1_900_000_031],
            ["pwd_auth_time": 1_899_999_699_000 as Int64],
            ["pwd_auth_time": 1_900_000_031_000 as Int64],
            ["exp": 1_900_000_010], ["scope": "openid"],
            ["scp": [RemoteTokenClaims.stepUpScope, "extra"]],
            ["client_id": "other"], ["azp": "other"],
            ["pwd_auth_time": NSNull()],
            ["iat": true], ["exp": "1900000600"]
        ]
        for changes in cases { XCTAssertThrowsError(try validate(fixture(changes))) }
    }
    func testStepUpRejectsAccountSwitchAndConflictingAliases() throws {
        for auth in [
            ["chatgpt_account_id": "other", "chatgpt_account_user_id": "user"],
            ["chatgpt_account_id": "account", "chatgpt_account_user_id": "other"],
            ["chatgpt_account_id": "account", "chatgpt_account_user_id": "user", "account_id": "other"]
        ] { XCTAssertThrowsError(try validate(fixture(["https://api.openai.com/auth": auth]))) }
    }
    func testOptionalClientMarkersAndConflicts() throws {
        XCTAssertNoThrow(try validate(fixture(["client_id": NSNull()])))
        XCTAssertNoThrow(try validate(fixture(["https://api.openai.com/auth": ["chatgpt_account_user_id": "user"]])))
        XCTAssertNoThrow(try validate(fixture(["client_id": NSNull(), "azp": "public-client"])))
        XCTAssertThrowsError(try validate(fixture(["client_id": NSNull(), "azp": "other"])))
        XCTAssertThrowsError(try validate(fixture(["client_id": "other", "azp": "public-client"])))
    }
    func testMalformedAndExpiredOrdinaryTokensFailClosed() throws {
        for token in ["", "a.b", "a..b", "a.@@.b", String(repeating: "a", count: 262_145)] {
            XCTAssertThrowsError(try validate(token))
        }
        XCTAssertThrowsError(try RemoteTokenClaims.parseOrdinary(accessToken: fixture(["exp": 1_900_000_060]), expectedClientID: "public-client", now: now))
    }
}
