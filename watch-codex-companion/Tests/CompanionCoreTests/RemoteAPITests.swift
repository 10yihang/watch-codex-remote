import Foundation
import XCTest
@testable import CompanionCore

// All inputs are synthetic; these tests never create a URLSession or send a request.
final class RemoteAPITests: XCTestCase {
    private let authorization = RemoteAccountAuthorization(accessToken: "synthetic-token", accountID: "workspace-id", accountUserID: "account-user")
    private let now: Int64 = 1_900_000_000
    private let enrollmentJSON = #"{"account_user_id":"account-user","client_id":"client-id","device_key_challenge":{"account_user_id":"account-user","audience":"remote_control_client_enrollment","challenge_expires_at":2000000000,"challenge_id":"challenge-id","challenge_token":"synthetic-challenge","client_id":"client-id","nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","purpose":"remote_control_client_enrollment","target_origin":"https://chatgpt.com","target_path":"/backend-api/codex/remote/control/client/enroll/finish"}}"#

    func testAuthorizationRejectsHeaderInjectionAndOversizeValues() throws {
        XCTAssertNoThrow(try authorization.validate())
        for invalid in ["", " token", "token ", "token\r\nX-Other: value", "token\t", "a\u{0000}b", "a\u{007f}b", "你好", String(repeating: "x", count: 16_385)] {
            for candidate in [
                RemoteAccountAuthorization(accessToken: invalid, accountID: "workspace-id", accountUserID: "account-user"),
                RemoteAccountAuthorization(accessToken: "token", accountID: invalid, accountUserID: "account-user"),
                RemoteAccountAuthorization(accessToken: "token", accountID: "workspace-id", accountUserID: invalid)
            ] { XCTAssertThrowsError(try candidate.validate()) }
        }
    }

    func testPostDispatchFailuresDoNotInviteMutationReplay() {
        for method in ["POST", "DELETE"] {
            for error in [RemoteAPIError.responseTooLarge, .invalidResponse, .httpStatus(500), .httpStatus(408)] {
                XCTAssertEqual(RemoteAPI.failureAfterDispatch(error, method: method), .outcomeUnknown)
            }
            XCTAssertEqual(RemoteAPI.failureAfterDispatch(RemoteAPIError.httpStatus(403), method: method), .httpStatus(403))
            XCTAssertEqual(RemoteAPI.failureAfterDispatch(CancellationError(), method: method), .outcomeUnknown)
        }
        XCTAssertEqual(RemoteAPI.failureAfterDispatch(RemoteAPIError.responseTooLarge, method: "GET"), .responseTooLarge)
    }

    func testPairingFormattingMatchesUpstream() throws {
        for code in ["abcd1234", "ABCD-1234", " ab-cd\t12\n34\r "] {
            XCTAssertEqual(try RemoteAPI.pairingBody(clientID: "client-id", code: code),
                           ["client_id": "client-id", "manual_pairing_code": "ABCD-1234"])
        }
    }

    func testPairingRejectsMalformedAndUnicodeInputs() {
        for code in ["", "ABCD123", "ABCD12345", "ABCD/1234", "ＡBCD1234", "ABCD\u{00a0}1234", "ABCD_1234", "ABCD💻1234", "ABCD\u{0000}1234"] {
            XCTAssertThrowsError(try RemoteAPI.pairingBody(clientID: "client-id", code: code))
        }
        XCTAssertThrowsError(try RemoteAPI.pairingBody(clientID: "../other", code: "ABCD1234"))
    }

    func testPathIDRejectsInjectionWithoutNormalization() throws {
        XCTAssertEqual(try RemoteAPI.pathID("host_A-123"), "host_A-123")
        XCTAssertEqual(try RemoteAPI.pathID(String(repeating: "a", count: 256)).count, 256)
        for value in ["", ".", "..", "../other", "a/b", "a\\b", "a%2Fb", "%2e%2e", "a?x=1", "a#x", "a&b", "a b", "a\n", "中文", "https://other", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try RemoteAPI.pathID(value))
        }
    }

    func testHostDecodingAndNameFallback() throws {
        let full = #"{"env_id":"env-id","display_name":"Mac Studio","host_name":"studio.local","name":"Studio","online":true,"busy":false,"app_server_version":"1.2.3","unknown_field":"ignored"}"#
        let host = try JSONDecoder().decode(RemoteHost.self, from: Data(full.utf8))
        XCTAssertEqual(host.id, "env-id")
        XCTAssertEqual(host.title, "Mac Studio")
        XCTAssertEqual(host.appServerVersion, "1.2.3")
        XCTAssertTrue(host.online)
        XCTAssertFalse(host.busy)
        for (extra, expected) in [
            (#", "display_name":"  ", "name":"Named Mac", "host_name":"hostname""#, "Named Mac"),
            (#", "name":"", "host_name":"hostname""#, "hostname"),
            ("", "env-id")
        ] {
            let json = #"{"env_id":"env-id","online":false,"busy":false"# + extra + "}"
            XCTAssertEqual(try JSONDecoder().decode(RemoteHost.self, from: Data(json.utf8)).title, expected)
        }
    }

    func testHostMissingOrInvalidStateFailsClosed() {
        for json in [#"{"env_id":"../other","online":true}"#, #"{"env_id":"env-id","online":"true","busy":false}"#, #"{"online":true,"busy":false}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(RemoteHost.self, from: Data(json.utf8)))
        }
    }

    func testEnrollmentResponseDecodesSnakeCaseAndValidatesBinding() throws {
        let start = try JSONDecoder().decode(RemoteEnrollmentStart.self, from: Data(enrollmentJSON.utf8))
        XCTAssertEqual(start.clientID, "client-id")
        XCTAssertEqual(start.accountUserID, "account-user")
        XCTAssertEqual(start.challenge.challengeToken, "synthetic-challenge")
        XCTAssertNil(start.challenge.deviceIdentityHash)
        XCTAssertNoThrow(try RemoteAPI.validateEnrollmentStart(start, authorization: authorization, refresh: false, nowEpoch: now))
        XCTAssertThrowsError(try RemoteAPI.validateEnrollmentStart(start, authorization: authorization, refresh: true, nowEpoch: now))
        XCTAssertThrowsError(try RemoteAPI.validateEnrollmentStart(start, authorization: authorization, refresh: false, nowEpoch: 2_000_000_000))
        let other = RemoteAccountAuthorization(accessToken: "token", accountID: "workspace-id", accountUserID: "other")
        XCTAssertThrowsError(try RemoteAPI.validateEnrollmentStart(start, authorization: other, refresh: false, nowEpoch: now))
    }

    func testEnrollmentResponseRejectsCrossAccountAndWrongTarget() throws {
        let changes: [(inout RemoteEnrollmentChallenge) -> Void] = [
            { $0.accountUserId = "other" }, { $0.clientId = "other" }, { $0.purpose = "other" },
            { $0.audience = "other" }, { $0.targetOrigin = "https://example.com" },
            { $0.targetPath += "/other" }, { $0.challengeId = "" }, { $0.challengeToken = "" }
        ]
        let start = try JSONDecoder().decode(RemoteEnrollmentStart.self, from: Data(enrollmentJSON.utf8))
        for change in changes {
            var challenge = start.challenge; change(&challenge)
            let value = RemoteEnrollmentStart(accountUserID: start.accountUserID, clientID: start.clientID, challenge: challenge)
            XCTAssertThrowsError(try RemoteAPI.validateEnrollmentStart(value, authorization: authorization, refresh: false, nowEpoch: now))
        }
    }
    func testFinishEnrollmentHasNoRequiredControllerToken() throws {
        let json = #"{"account_user_id":"account-user","client_id":"client-id","scopes":["remote_control_controller_websocket"]}"#
        let finish = try JSONDecoder().decode(RemoteEnrollmentFinish.self, from: Data(json.utf8))
        let record = RemoteEnrollmentRecord(accountUserId: "account-user", algorithm: "ecdsa_p256_sha256", clientId: "client-id", keyId: "key", protectionClass: "hardware_secure_enclave", publicKeySpkiDerBase64: "test")
        XCTAssertNoThrow(try finish.validate(record: record))
        var other = record; other.clientId = "another-controller"
        XCTAssertThrowsError(try finish.validate(record: other))
    }
    func testEnrollmentAcceptsOnlyExplicitTokenIdentityAlias() throws {
        let start = try JSONDecoder().decode(RemoteEnrollmentStart.self, from: Data(enrollmentJSON.utf8))
        let alias = RemoteAccountAuthorization(accessToken: "synthetic-token", accountID: "workspace-id", accountUserID: "different-primary", tokenUserID: "account-user")
        XCTAssertNoThrow(try RemoteAPI.validateEnrollmentStart(start, authorization: alias, refresh: false, nowEpoch: now))
        let unrelated = RemoteAccountAuthorization(accessToken: "synthetic-token", accountID: "workspace-id", accountUserID: "different-primary", tokenUserID: "unrelated")
        XCTAssertThrowsError(try RemoteAPI.validateEnrollmentStart(start, authorization: unrelated, refresh: false, nowEpoch: now))
    }

    func testHostOptionalStateDefaultsClosed() throws {
        for json in [#"{"env_id":"env-id"}"#, #"{"env_id":"env-id","online":null,"busy":null}"#] {
            let host = try JSONDecoder().decode(RemoteHost.self, from: Data(json.utf8))
            XCTAssertFalse(host.online)
            XCTAssertFalse(host.busy)
        }
        let host = try JSONDecoder().decode(RemoteHost.self, from: Data(#"{"env_id":"env-id","online":true}"#.utf8))
        XCTAssertTrue(host.online)
        XCTAssertFalse(host.busy)
    }

    func testReadTransportFailuresHaveSafeCategoriesWithoutMutationReplay() {
        let cases: [(Error, RemoteAPIError)] = [
            (CancellationError(), .cancelled), (URLError(.cancelled), .cancelled),
            (URLError(.timedOut), .timedOut), (URLError(.notConnectedToInternet), .transportFailed),
            (RemoteAPIError.httpStatus(403), .httpStatus(403))
        ]
        for (error, expected) in cases {
            XCTAssertEqual(RemoteAPI.failureAfterDispatch(error, method: "GET"), expected)
        }
        for error in [URLError(.timedOut), URLError(.cancelled), URLError(.networkConnectionLost)] {
            for method in ["POST", "DELETE"] {
                XCTAssertEqual(RemoteAPI.failureAfterDispatch(error, method: method), .outcomeUnknown)
            }
        }
    }

}
