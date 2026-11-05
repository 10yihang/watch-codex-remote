import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// In-memory protocol values only. No credential discovery, key creation, or persistence.
public struct RemoteEnrollmentRecord: Codable, Equatable, Sendable {
    public var accountUserId: String
    public var algorithm: String
    public var clientId: String
    public var keyId: String
    public var protectionClass: String
    public var publicKeySpkiDerBase64: String
}

public struct RemoteEnrollmentChallenge: Codable, Sendable {
    public var accountUserId: String
    public var audience: String
    public var challengeExpiresAt: Int64
    public var challengeId: String
    public var challengeToken: String
    public var clientId: String
    public var deviceIdentityHash: String?
    public var nonce: String
    public var purpose: String
    public var targetOrigin: String
    public var targetPath: String
    enum CodingKeys: String, CodingKey {
        case accountUserId = "account_user_id", audience, challengeExpiresAt = "challenge_expires_at"
        case challengeId = "challenge_id", challengeToken = "challenge_token", clientId = "client_id"
        case deviceIdentityHash = "device_identity_hash", nonce, purpose
        case targetOrigin = "target_origin", targetPath = "target_path"
    }
}

public struct RemoteConnectionChallenge: Codable, Sendable {
    public var accountUserId: String
    public var audience: String
    public var clientId: String
    public var nonce: String
    public var purpose: String
    public var scopes: [String]
    public var sessionId: String
    public var targetOrigin: String
    public var targetPath: String
    public var tokenExpiresAt: Int64
    public var tokenSha256Base64url: String
}

public struct RemoteControlSession: Codable, Sendable {
    public var accountUserId: String
    public var clientId: String
    public var expiresAt: String
    public var remoteControlToken: String
    public var scopes: [String]
    enum CodingKeys: String, CodingKey {
        case accountUserId = "account_user_id", clientId = "client_id", expiresAt = "expires_at"
        case remoteControlToken = "remote_control_token", scopes
    }
}

public struct RemoteDeviceKeyProof: Codable, Sendable {
    public var algorithm: String
    public var challengeToken: String
    public var keyId: String
    public var signatureDerBase64: String
    public var signedPayloadBase64: String
    enum CodingKeys: String, CodingKey {
        case algorithm, challengeToken = "challenge_token", keyId = "key_id"
        case signatureDerBase64 = "signature_der_base64", signedPayloadBase64 = "signed_payload_base64"
    }
}

public enum RemoteSigningError: Error, Equatable {
    case invalidRecord, invalidNonce, invalidDigest, mismatchedChallenge, expiredChallenge
    case missingIdentityHash, mismatchedIdentity, invalidSession, unsupportedCryptography
}

public enum RemoteSigning {
    public static let sessionScope = "remote_control_controller_websocket"
    private static let domain = "codex-device-key-sign-payload/v1"
    private static let enrollmentPurpose = "remote_control_client_enrollment"
    private static let connectionPurpose = "remote_control_client_websocket"
    private static let basePath = "/backend-api/codex/remote/control/client"

    public static func deviceIdentityHash(record: RemoteEnrollmentRecord) throws -> String {
        try validateRecord(record)
        let identity = object([
            ("algorithm", quote(record.algorithm)), ("keyId", quote(record.keyId)),
            ("protectionClass", quote(record.protectionClass)),
            ("publicKeySpkiDerBase64", quote(record.publicKeySpkiDerBase64))
        ])
        return try hash(Data(identity.utf8))
    }

    public static func enrollmentPayload(record: RemoteEnrollmentRecord, challenge: RemoteEnrollmentChallenge,
                                         refresh: Bool, nowEpoch: Int64) throws -> Data {
        try validateNonce(challenge.nonce)
        guard challenge.purpose == enrollmentPurpose, challenge.audience == enrollmentPurpose,
              challenge.accountUserId == record.accountUserId, challenge.clientId == record.clientId,
              challenge.targetOrigin == "https://chatgpt.com",
              challenge.targetPath == basePath + (refresh ? "/refresh/finish" : "/enroll/finish"),
              !challenge.challengeId.isEmpty, !challenge.challengeToken.isEmpty else {
            throw RemoteSigningError.mismatchedChallenge
        }
        guard challenge.challengeExpiresAt > nowEpoch else { throw RemoteSigningError.expiredChallenge }
        if refresh && challenge.deviceIdentityHash == nil { throw RemoteSigningError.missingIdentityHash }
        let identityHash = try deviceIdentityHash(record: record)
        guard challenge.deviceIdentityHash == nil || challenge.deviceIdentityHash == identityHash else {
            throw RemoteSigningError.mismatchedIdentity
        }
        return envelope([
            ("accountUserId", quote(challenge.accountUserId)), ("audience", quote(enrollmentPurpose)),
            ("challengeExpiresAt", String(challenge.challengeExpiresAt)), ("challengeId", quote(challenge.challengeId)),
            ("clientId", quote(challenge.clientId)), ("deviceIdentitySha256Base64url", quote(identityHash)),
            ("nonce", quote(challenge.nonce)), ("targetOrigin", quote(challenge.targetOrigin)),
            ("targetPath", quote(challenge.targetPath)), ("type", quote("remoteControlClientEnrollment"))
        ])
    }

    public static func validateSession(record: RemoteEnrollmentRecord, session: RemoteControlSession,
                                       nowEpoch: Int64) throws -> Int64 {
        try validateRecord(record)
        guard session.accountUserId == record.accountUserId, session.clientId == record.clientId,
              session.scopes == [sessionScope], !session.remoteControlToken.isEmpty,
              !session.remoteControlToken.contains(where: { $0.isWhitespace }) else {
            throw RemoteSigningError.invalidSession
        }
        let wholeSeconds = try validatedWholeSecondTimestamp(session.expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: wholeSeconds) else {
            throw RemoteSigningError.invalidSession
        }
        let expiry = Int64(floor(date.timeIntervalSince1970))
        guard expiry > nowEpoch else { throw RemoteSigningError.invalidSession }
        return expiry
    }

    public static func connectionPayload(record: RemoteEnrollmentRecord, session: RemoteControlSession,
                                         challenge: RemoteConnectionChallenge, nowEpoch: Int64) throws -> Data {
        let expiry = try validateSession(record: record, session: session, nowEpoch: nowEpoch)
        guard let suppliedDigest = decodeBase64URL(challenge.tokenSha256Base64url), suppliedDigest.count == 32 else {
            throw RemoteSigningError.invalidDigest
        }
        let expectedDigest = try sha256(Data(session.remoteControlToken.utf8))
        // Compare every digest byte, without stopping at the first difference.
        let digestDifference = zip(suppliedDigest, expectedDigest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard challenge.accountUserId == record.accountUserId, challenge.clientId == record.clientId,
              challenge.tokenExpiresAt == expiry, !challenge.sessionId.isEmpty, digestDifference == 0 else {
            throw RemoteSigningError.mismatchedChallenge
        }
        return try connectionContractPayload(challenge)
    }

    // Internal contract encoder for golden-vector tests; callers sign only connectionPayload's validated result.
    static func connectionContractPayload(_ challenge: RemoteConnectionChallenge) throws -> Data {
        try validateNonce(challenge.nonce)
        guard let digest = decodeBase64URL(challenge.tokenSha256Base64url), digest.count == 32 else {
            throw RemoteSigningError.invalidDigest
        }
        guard challenge.purpose == connectionPurpose, challenge.audience == connectionPurpose,
              challenge.targetOrigin == "https://chatgpt.com", challenge.targetPath == basePath,
              challenge.scopes == [sessionScope] else { throw RemoteSigningError.mismatchedChallenge }
        return envelope([
            ("accountUserId", quote(challenge.accountUserId)), ("audience", quote(challenge.audience)),
            ("clientId", quote(challenge.clientId)), ("nonce", quote(challenge.nonce)),
            ("scopes", "[" + quote(sessionScope) + "]"), ("sessionId", quote(challenge.sessionId)),
            ("targetOrigin", quote(challenge.targetOrigin)), ("targetPath", quote(challenge.targetPath)),
            ("tokenExpiresAt", String(challenge.tokenExpiresAt)),
            ("tokenSha256Base64url", quote(challenge.tokenSha256Base64url)),
            ("type", quote("remoteControlClientConnection"))
        ])
    }

    #if canImport(CryptoKit)
    public static func proof(record: RemoteEnrollmentRecord, challengeToken: String, payload: Data,
                             privateKey: P256.Signing.PrivateKey) throws -> RemoteDeviceKeyProof {
        try validateRecord(record)
        guard Data(base64Encoded: record.publicKeySpkiDerBase64) == privateKey.publicKey.derRepresentation,
              !challengeToken.isEmpty, !payload.isEmpty else { throw RemoteSigningError.mismatchedIdentity }
        return RemoteDeviceKeyProof(algorithm: record.algorithm, challengeToken: challengeToken, keyId: record.keyId,
                                    signatureDerBase64: try privateKey.signature(for: payload).derRepresentation.base64EncodedString(),
                                    signedPayloadBase64: payload.base64EncodedString())
    }
    #endif

    private static func validateRecord(_ record: RemoteEnrollmentRecord) throws {
        guard record.algorithm == "ecdsa_p256_sha256", !record.accountUserId.isEmpty, !record.clientId.isEmpty,
              !record.keyId.isEmpty, !record.protectionClass.isEmpty, !record.publicKeySpkiDerBase64.isEmpty else {
            throw RemoteSigningError.invalidRecord
        }
    }

    private static func hash(_ data: Data) throws -> String { base64URL(try sha256(data)) }

    private static func sha256(_ data: Data) throws -> Data {
        #if canImport(CryptoKit)
        return Data(SHA256.hash(data: data))
        #else
        throw RemoteSigningError.unsupportedCryptography
        #endif
    }

    private static func validatedWholeSecondTimestamp(_ value: String) throws -> String {
        // ISO8601DateFormatter can normalize invalid dates. Validate before parsing.
        // Leap seconds are deliberately unsupported; fractions do not affect the signed integer epoch.
        let pattern = #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})\z"#
        guard value.utf8.count <= 128, value.range(of: pattern, options: .regularExpression) != nil else {
            throw RemoteSigningError.invalidSession
        }
        let bytes = Array(value.utf8)
        func number(_ range: Range<Int>) -> Int {
            bytes[range].reduce(0) { $0 * 10 + Int($1 - 48) }
        }
        let year = number(0..<4), month = number(5..<7), day = number(8..<10)
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...12).contains(month), day >= 1, day <= days[month - 1],
              number(11..<13) <= 23, number(14..<16) <= 59, number(17..<19) <= 59 else {
            throw RemoteSigningError.invalidSession
        }
        if bytes.last != 90 {
            let offset = bytes.count - 6
            guard number((offset + 1)..<(offset + 3)) <= 23,
                  number((offset + 4)..<(offset + 6)) <= 59 else { throw RemoteSigningError.invalidSession }
        }
        // Removing a validated fraction prevents floating-point rounding into the next second.
        return value.replacingOccurrences(of: #"\.[0-9]+"#, with: "", options: .regularExpression)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || $0 == 45 || $0 == 95 }), value.count % 4 != 1 else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), base64URL(data) == value else { return nil }
        return data
    }

    private static func validateNonce(_ nonce: String) throws {
        guard let bytes = decodeBase64URL(nonce), bytes.count >= 32 else { throw RemoteSigningError.invalidNonce }
    }

    // serde_json emits insertion order and unescaped slashes. JSONEncoder does not guarantee key order.
    private static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { quote($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }
    private static func envelope(_ fields: [(String, String)]) -> Data {
        Data(object([("domain", quote(domain)), ("payload", object(fields))]).utf8)
    }
    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 0...31: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
