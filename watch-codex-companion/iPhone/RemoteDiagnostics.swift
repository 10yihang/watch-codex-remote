import CryptoKit
import Foundation

enum RemoteDiagnostics {
    // User-triggered, memory-only self-check. Never enrolls, persists a key or opens a socket.
    static func run() throws -> String {
        let key = P256.Signing.PrivateKey()
        let record = RemoteEnrollmentRecord(accountUserId: "offline_account", algorithm: "ecdsa_p256_sha256",
            clientId: "offline_client", keyId: "offline_ephemeral_key", protectionClass: "offline_test_only",
            publicKeySpkiDerBase64: key.publicKey.derRepresentation.base64EncodedString())
        let now = Int64(Date().timeIntervalSince1970)
        let challenge = RemoteEnrollmentChallenge(accountUserId: record.accountUserId,
            audience: "remote_control_client_enrollment", challengeExpiresAt: now + 60,
            challengeId: "offline_challenge", challengeToken: "offline_token", clientId: record.clientId,
            deviceIdentityHash: nil, nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            purpose: "remote_control_client_enrollment", targetOrigin: "https://chatgpt.com",
            targetPath: "/backend-api/codex/remote/control/client/enroll/finish")
        let payload = try RemoteSigning.enrollmentPayload(record: record, challenge: challenge, refresh: false, nowEpoch: now)
        let proof = try RemoteSigning.proof(record: record, challengeToken: challenge.challengeToken, payload: payload, privateKey: key)
        guard let signatureData = Data(base64Encoded: proof.signatureDerBase64),
              key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signatureData), for: payload) else {
            throw RemoteSigningError.mismatchedIdentity
        }
        var relay = try RemoteRelayCodec(clientID: record.clientId, environmentID: "offline_host")
        let frame = try relay.envelope(RemoteRelayCodec.request(id: 1, method: "thread/list"))
        guard try RemoteRelayCodec.object(frame)["type"] as? String == "client_message" else {
            throw RemoteRelayError.malformedFrame
        }
        return "本机签名、验签与 relay 编码检查通过。没有联网、保存密钥或验证真实主机。"
    }
}
