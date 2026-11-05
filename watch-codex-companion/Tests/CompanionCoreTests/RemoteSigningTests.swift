import Foundation
import XCTest
@testable import CompanionCore
#if canImport(CryptoKit)
import CryptoKit
#endif

final class RemoteSigningTests: XCTestCase {
    private let now: Int64 = 1_900_000_000
    private let nonce = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private var record: RemoteEnrollmentRecord {
        RemoteEnrollmentRecord(accountUserId: "account-user", algorithm: "ecdsa_p256_sha256", clientId: "client-id",
                               keyId: "rcodex_osn_key-id", protectionClass: "os_protected_nonextractable",
                               publicKeySpkiDerBase64: "public-key")
    }
    private var enrollment: RemoteEnrollmentChallenge {
        RemoteEnrollmentChallenge(accountUserId: "account-user", audience: "remote_control_client_enrollment",
                                  challengeExpiresAt: 2_000_000_000, challengeId: "challenge-id", challengeToken: "opaque-token",
                                  clientId: "client-id", deviceIdentityHash: nil, nonce: nonce,
                                  purpose: "remote_control_client_enrollment", targetOrigin: "https://chatgpt.com",
                                  targetPath: "/backend-api/codex/remote/control/client/enroll/finish")
    }
    private var connection: RemoteConnectionChallenge {
        RemoteConnectionChallenge(accountUserId: "account-user", audience: "remote_control_client_websocket",
                                  clientId: "client-id", nonce: nonce, purpose: "remote_control_client_websocket",
                                  scopes: [RemoteSigning.sessionScope], sessionId: "session-id", targetOrigin: "https://chatgpt.com",
                                  targetPath: "/backend-api/codex/remote/control/client", tokenExpiresAt: 2_000_000_000,
                                  tokenSha256Base64url: nonce)
    }
    private var session: RemoteControlSession {
        RemoteControlSession(accountUserId: "account-user", clientId: "client-id", expiresAt: "2033-05-18T03:33:20Z",
                             remoteControlToken: "session-token", scopes: [RemoteSigning.sessionScope])
    }

    func testUpstreamWebSocketGoldenVector() throws {
        let expected = #"{"domain":"codex-device-key-sign-payload/v1","payload":{"accountUserId":"account-user","audience":"remote_control_client_websocket","clientId":"client-id","nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","scopes":["remote_control_controller_websocket"],"sessionId":"session-id","targetOrigin":"https://chatgpt.com","targetPath":"/backend-api/codex/remote/control/client","tokenExpiresAt":2000000000,"tokenSha256Base64url":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","type":"remoteControlClientConnection"}}"#
        XCTAssertEqual(try RemoteSigning.connectionContractPayload(connection), Data(expected.utf8))
    }

    func testCanonicalEscapingPreservesUnicodeAndSlashes() throws {
        var value = connection
        value.accountUserId = "你好/\"\\\n\u{0001}"
        let payload = try RemoteSigning.connectionContractPayload(value)
        let text = try XCTUnwrap(String(data: payload, encoding: .utf8))
        XCTAssertTrue(text.contains(#"你好/\"\\\n\u0001"#))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let object = try XCTUnwrap(envelope["payload"] as? [String: Any])
        XCTAssertEqual(object["accountUserId"] as? String, value.accountUserId)
    }

    func testRejectsMalformedNonceDigestAndContract() {
        for nonce in ["", "abc", self.nonce + "=", String(repeating: "A", count: 42) + "B", "not base64"] {
            var value = connection; value.nonce = nonce
            XCTAssertThrowsError(try RemoteSigning.connectionContractPayload(value))
        }
        var value = connection; value.tokenSha256Base64url = "abc"
        XCTAssertThrowsError(try RemoteSigning.connectionContractPayload(value))
        let changes: [(inout RemoteConnectionChallenge) -> Void] = [
            { $0.targetOrigin = "https://example.com" }, { $0.targetPath += "/other" },
            { $0.purpose = "other" }, { $0.audience = "other" }, { $0.scopes.append("other") }
        ]
        for change in changes {
            var value = connection; change(&value)
            XCTAssertThrowsError(try RemoteSigning.connectionContractPayload(value))
        }
    }

    func testWireCodingUsesCorrectCase() throws {
        let encoded = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["account_user_id"] as? String, "account-user")
        XCTAssertNil(object["accountUserId"])
        XCTAssertEqual(try JSONDecoder().decode(RemoteControlSession.self, from: encoded).clientId, "client-id")
        let challengeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(enrollment)) as? [String: Any])
        XCTAssertNotNil(challengeObject["challenge_expires_at"])
        let connectionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(connection)) as? [String: Any])
        XCTAssertNotNil(connectionObject["tokenSha256Base64url"])
    }

    func testSessionBindingExpirationAndScope() throws {
        XCTAssertEqual(try RemoteSigning.validateSession(record: record, session: session, nowEpoch: now), 2_000_000_000)
        let changes: [(inout RemoteControlSession) -> Void] = [
            { $0.accountUserId = "other" }, { $0.clientId = "other" }, { $0.scopes = [] },
            { $0.expiresAt = "invalid" }, { $0.expiresAt = "2020-01-01T00:00:00Z" },
            { $0.remoteControlToken = "" }, { $0.remoteControlToken = "token\n" }
        ]
        for change in changes {
            var value = session; change(&value)
            XCTAssertThrowsError(try RemoteSigning.validateSession(record: record, session: value, nowEpoch: now))
        }
        XCTAssertThrowsError(try RemoteSigning.validateSession(record: record, session: session, nowEpoch: 2_000_000_000))
    }

    func testStrictExpiryRejectsNormalizedDatesTimesAndZones() {
        for timestamp in [
            "2023-02-29T03:33:20Z", "2100-02-29T03:33:20Z", "2033-02-31T03:33:20Z",
            "2033-04-31T03:33:20Z", "2033-00-18T03:33:20Z", "2033-13-18T03:33:20Z",
            "2033-05-00T03:33:20Z", "2033-05-18T24:00:00Z", "2033-05-18T03:60:20Z",
            "2033-05-18T03:33:60Z", "2033-05-18T03:33:20+24:00", "2033-05-18T03:33:20+00:60",
            "2033-05-18T03:33:20", "2033-05-18 03:33:20Z", "2033-05-18T03:33:20.Z",
            "2033-05-18T03:33:20Z\n", " 2033-05-18T03:33:20Z", "2033-05-18T03:33:20+0000"
        ] {
            var value = session; value.expiresAt = timestamp
            // Epoch zero ensures malformed older dates fail validation, not just expiration.
            XCTAssertThrowsError(try RemoteSigning.validateSession(record: record, session: value, nowEpoch: 0), timestamp)
        }
    }

    func testExpiryFractionsAndOffsetsKeepExactWholeSecondEpoch() throws {
        for timestamp in ["2033-05-18T03:33:20.123Z", "2033-05-18T03:33:20.999999999Z",
                          "2033-05-18T05:33:20.123+02:00", "2033-05-18T00:03:20-03:30"] {
            var value = session; value.expiresAt = timestamp
            XCTAssertEqual(try RemoteSigning.validateSession(record: record, session: value, nowEpoch: now), 2_000_000_000)
        }
        for timestamp in ["2000-02-29T00:00:00Z", "2024-02-29T00:00:00Z"] {
            var value = session; value.expiresAt = timestamp
            XCTAssertNoThrow(try RemoteSigning.validateSession(record: record, session: value, nowEpoch: 0))
        }
    }

    #if canImport(CryptoKit)
    func testUpstreamIdentityAndEnrollmentGoldenVectors() throws {
        XCTAssertEqual(try RemoteSigning.deviceIdentityHash(record: record), "Vq0Okx8un5zFrEAPEVFV4cTunCI8P0dD-8Ik6CmmBpI")
        let expected = #"{"domain":"codex-device-key-sign-payload/v1","payload":{"accountUserId":"account-user","audience":"remote_control_client_enrollment","challengeExpiresAt":2000000000,"challengeId":"challenge-id","clientId":"client-id","deviceIdentitySha256Base64url":"Vq0Okx8un5zFrEAPEVFV4cTunCI8P0dD-8Ik6CmmBpI","nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","targetOrigin":"https://chatgpt.com","targetPath":"/backend-api/codex/remote/control/client/enroll/finish","type":"remoteControlClientEnrollment"}}"#
        XCTAssertEqual(try RemoteSigning.enrollmentPayload(record: record, challenge: enrollment, refresh: false, nowEpoch: now), Data(expected.utf8))
    }

    func testEnrollmentRejectsBindingAndExpirationChanges() throws {
        let changes: [(inout RemoteEnrollmentChallenge) -> Void] = [
            { $0.accountUserId = "other" }, { $0.clientId = "other" }, { $0.targetOrigin = "https://example.com" },
            { $0.targetPath += "/other" }, { $0.purpose = "other" }, { $0.audience = "other" },
            { $0.deviceIdentityHash = self.nonce }, { $0.challengeExpiresAt = self.now },
            { $0.challengeId = "" }, { $0.challengeToken = "" }
        ]
        for change in changes {
            var value = enrollment; change(&value)
            XCTAssertThrowsError(try RemoteSigning.enrollmentPayload(record: record, challenge: value, refresh: false, nowEpoch: now))
        }
        var value = enrollment; value.targetPath = "/backend-api/codex/remote/control/client/refresh/finish"
        XCTAssertThrowsError(try RemoteSigning.enrollmentPayload(record: record, challenge: value, refresh: true, nowEpoch: now))
        value.deviceIdentityHash = try RemoteSigning.deviceIdentityHash(record: record)
        XCTAssertNoThrow(try RemoteSigning.enrollmentPayload(record: record, challenge: value, refresh: true, nowEpoch: now))
    }

    func testWebSocketBindsActualTokenAndSession() throws {
        var challenge = connection
        challenge.tokenSha256Base64url = "wQHpEUaclpFxBAtQ1wVDMTz5aP3vW6zHgHdvj7OZqzY"
        XCTAssertEqual(try RemoteSigning.connectionPayload(record: record, session: session, challenge: challenge, nowEpoch: now),
                       try RemoteSigning.connectionContractPayload(challenge))
        let changes: [(inout RemoteConnectionChallenge) -> Void] = [
            { $0.accountUserId = "other" }, { $0.clientId = "other" }, { $0.tokenExpiresAt += 1 },
            { $0.tokenSha256Base64url = self.nonce }, { $0.sessionId = "" }
        ]
        for change in changes {
            var value = challenge; change(&value)
            XCTAssertThrowsError(try RemoteSigning.connectionPayload(record: record, session: session, challenge: value, nowEpoch: now))
        }
    }

    func testEphemeralProofUsesDERAndBindsPublicKey() throws {
        // Test-only ephemeral key. Nothing is saved, enrolled, or sent.
        let key = P256.Signing.PrivateKey()
        var value = record; value.publicKeySpkiDerBase64 = key.publicKey.derRepresentation.base64EncodedString()
        let payload = try RemoteSigning.enrollmentPayload(record: value, challenge: enrollment, refresh: false, nowEpoch: now)
        let proof = try RemoteSigning.proof(record: value, challengeToken: enrollment.challengeToken, payload: payload, privateKey: key)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: XCTUnwrap(Data(base64Encoded: proof.signatureDerBase64)))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: payload))
        XCTAssertEqual(Data(base64Encoded: proof.signedPayloadBase64), payload)
        XCTAssertThrowsError(try RemoteSigning.proof(record: record, challengeToken: "token", payload: payload, privateKey: key))
    }
    #endif
}
