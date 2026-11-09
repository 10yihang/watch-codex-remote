// Claim shapes adapted from NightBlood Remote, commit
// 4824aceb1cd04ac521f7f0342771c20edad60dac (MIT; see ThirdParty).
import Foundation

public enum RemoteTokenClaimsError: Error, LocalizedError, Sendable {
    case malformed, accountMismatch, clientMismatch, expired, stale, scopeMismatch
    public var errorDescription: String? {
        switch self {
        case .malformed: return "The token claims are missing or malformed."
        case .accountMismatch: return "Sign-in returned a different account."
        case .clientMismatch: return "The token is not bound to this OAuth client."
        case .expired: return "Sign in again to obtain a fresh access token."
        case .stale: return "Remote authorization requires fresh authentication."
        case .scopeMismatch: return "The token does not have the expected enrollment scope."
        }
    }
}

public struct RemoteAccountClaims: Sendable, Equatable {
    public let accountID: String
    public let accountUserID: String
    public let tokenUserID: String?
    public let expiresAt: Date
}

/// Unverified payload decoding for routing and consistency ONLY. This does not
/// authenticate a JWT, validate its signature, or grant permission. The HTTPS
/// service remains authoritative and must verify every credential and proof.
public enum RemoteTokenClaims {
    public static let stepUpScope = "codex.remote_control.enroll"

    public static func parseOrdinary(
        accessToken: String, expectedClientID: String,
        now: Date = Date(), minimumValidity: TimeInterval = 60
    ) throws -> RemoteAccountClaims {
        let claims = try payload(accessToken)
        try client(claims, expected: expectedClientID)
        guard minimumValidity.isFinite, minimumValidity >= 0,
              let expiry = claims.exp, expiry.isFinite,
              expiry > now.timeIntervalSince1970 + minimumValidity else {
            throw RemoteTokenClaimsError.expired
        }
        let account = try account(claims)
        if let userID = claims.auth?.user_id, !valid(userID) { throw RemoteTokenClaimsError.malformed }
        return RemoteAccountClaims(accountID: account.0, accountUserID: account.1,
                                   tokenUserID: claims.auth?.user_id, expiresAt: Date(timeIntervalSince1970: expiry))
    }

    public static func validateStepUp(
        rawValue: String, accountID: String, accountUserID: String,
        clientID: String, now: Date = Date()
    ) throws {
        let claims = try payload(rawValue)
        try client(claims, expected: clientID)
        guard let auth = claims.auth,
              let user = auth.chatgpt_account_user_id ?? auth.account_user_id,
              valid(user) else { throw RemoteTokenClaimsError.malformed }
        // Pinned step-up claims require account-user identity. Workspace claims
        // are optional here; reject any present values that disagree with the
        // workspace explicitly constrained in the authorization request.
        let workspaces = [auth.chatgpt_account_id, auth.account_id].compactMap { $0 }
        let users = [auth.chatgpt_account_user_id, auth.account_user_id].compactMap { $0 }
        guard user == accountUserID, valid(accountID),
              workspaces.allSatisfy({ $0 == accountID }),
              users.allSatisfy({ $0 == accountUserID }) else {
            throw RemoteTokenClaimsError.accountMismatch
        }
        let timestamp = now.timeIntervalSince1970
        guard let expiry = claims.exp, expiry.isFinite, expiry > timestamp + 10 else {
            throw RemoteTokenClaimsError.expired
        }
        guard let issued = claims.iat, let passwordMS = claims.passwordTime,
              issued.isFinite, passwordMS.isFinite,
              issued <= timestamp + 30, issued >= timestamp - 300,
              passwordMS / 1000 <= timestamp + 30,
              passwordMS / 1000 >= timestamp - 300,
              expiry > issued else { throw RemoteTokenClaimsError.stale }
        var scopes = Set(claims.scope?.split(whereSeparator: { $0.isWhitespace }).map(String.init) ?? [])
        scopes.formUnion(claims.scp ?? [])
        guard scopes == [stepUpScope] else { throw RemoteTokenClaimsError.scopeMismatch }
    }

    private struct Claims: Decodable {
        let exp: Double?
        let iat: Double?
        let passwordTime: Double?
        let clientID: String?
        let authorizedParty: String?
        let auth: Auth?
        let scope: String?
        let scp: [String]?
        enum CodingKeys: String, CodingKey {
            case exp, iat, scope, scp
            case passwordTime = "pwd_auth_time", clientID = "client_id", authorizedParty = "azp"
            case auth = "https://api.openai.com/auth"
        }
    }

    private static func payload(_ token: String) throws -> Claims {
        guard token.utf8.count <= 262_144 else { throw RemoteTokenClaimsError.malformed }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        } }) else { throw RemoteTokenClaimsError.malformed }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let claims = try? JSONDecoder().decode(Claims.self, from: data) else {
            throw RemoteTokenClaimsError.malformed
        }
        return claims
    }

    private static func client(_ claims: Claims, expected: String) throws {
        let values = [claims.clientID, claims.authorizedParty].compactMap { $0 }
        // Some service tokens omit these markers. Their client binding comes
        // from our exact-client PKCE exchange over HTTPS, not this decoder.
        // Any markers that ARE present must agree, including with each other.
        guard valid(expected), values.allSatisfy({ $0 == expected }) else {
            throw RemoteTokenClaimsError.clientMismatch
        }
    }

    private struct Auth: Decodable {
        let chatgpt_account_id: String?
        let account_id: String?
        let chatgpt_account_user_id: String?
        let account_user_id: String?
        let user_id: String?
    }

    private static func account(_ claims: Claims) throws -> (String, String) {
        guard let auth = claims.auth,
              let id = auth.chatgpt_account_id ?? auth.account_id,
              let user = auth.chatgpt_account_user_id ?? auth.account_user_id,
              valid(id), valid(user) else { throw RemoteTokenClaimsError.malformed }
        guard auth.chatgpt_account_id == nil || auth.account_id == nil || auth.chatgpt_account_id == auth.account_id,
              auth.chatgpt_account_user_id == nil || auth.account_user_id == nil || auth.chatgpt_account_user_id == auth.account_user_id else {
            throw RemoteTokenClaimsError.accountMismatch
        }
        return (id, user)
    }

    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4096 && value.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7e }
    }
}
