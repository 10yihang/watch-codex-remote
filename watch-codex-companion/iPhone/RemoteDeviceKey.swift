import CryptoKit
import Foundation
import Security

// Dormant provider: no launch-time calls and no approved iOS Remote enrollment flow yet.
// Creating a persistent credential must only follow explicit user authorization.
enum RemoteDeviceKey {
    struct Identity: Codable, Equatable {
        let algorithm: String
        let keyId: String
        let protectionClass: String
        let publicKeySpkiDerBase64: String
    }

    enum Failure: Error {
        case unavailable, invalidIdentity, missingKey, invalidStoredKey, emptyPayload
        case keychain(OSStatus)
        case accessControl, cryptography
    }

    private struct StoredKey: Codable {
        let identity: Identity
        // Secure Enclave's device-bound encrypted representation, not an exportable scalar.
        let wrappedKey: Data
    }

    private static let service = "com.watchcodex.companion.remote-device-key.v1"
    private static let keyPrefix = "watch_codex_ios_se_"

    static func create() throws -> Identity {
        guard SecureEnclave.isAvailable else { throw Failure.unavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error
        ) else {
            _ = error?.takeRetainedValue()
            throw Failure.accessControl
        }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do { key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access) }
        catch { throw Failure.cryptography }
        let identity = Identity(
            algorithm: "ecdsa_p256_sha256",
            keyId: keyPrefix + UUID().uuidString.lowercased(),
            protectionClass: "os_protected_nonextractable",
            publicKeySpkiDerBase64: key.publicKey.derRepresentation.base64EncodedString()
        )
        try validate(identity, publicKey: key.publicKey)
        let stored = StoredKey(identity: identity, wrappedKey: key.dataRepresentation)
        var attributes = try query(keyId: identity.keyId)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecValueData as String] = try JSONEncoder().encode(stored)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        return identity
    }

    static func load(keyId: String) throws -> Identity {
        try read(keyId: keyId).identity
    }

    // The caller must first validate the Remote challenge and build its canonical payload.
    // CryptoKit hashes these payload bytes with SHA-256 exactly once.
    static func sign(record: RemoteEnrollmentRecord, payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw Failure.emptyPayload }
        let stored = try read(keyId: record.keyId)
        let expected = Identity(algorithm: record.algorithm, keyId: record.keyId,
                                protectionClass: record.protectionClass,
                                publicKeySpkiDerBase64: record.publicKeySpkiDerBase64)
        guard stored.identity == expected else { throw Failure.invalidIdentity }
        let key = try restore(stored)
        do { return try key.signature(for: payload).derRepresentation }
        catch { throw Failure.cryptography }
    }

    // Deletes only this app's wrapped key record. Does not revoke any server enrollment.
    static func remove(keyId: String) throws {
        let status = SecItemDelete(try query(keyId: keyId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }

    private static func query(keyId: String) throws -> [String: Any] {
        guard keyId.hasPrefix(keyPrefix),
              let uuid = UUID(uuidString: String(keyId.dropFirst(keyPrefix.count))),
              keyId == keyPrefix + uuid.uuidString.lowercased() else { throw Failure.invalidIdentity }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: keyId,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true]
    }

    private static func read(keyId: String) throws -> StoredKey {
        guard SecureEnclave.isAvailable else { throw Failure.unavailable }
        var attributes = try query(keyId: keyId)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw Failure.missingKey }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let bytes = result as? Data,
              let stored = try? JSONDecoder().decode(StoredKey.self, from: bytes),
              stored.identity.keyId == keyId else { throw Failure.invalidStoredKey }
        _ = try restore(stored)
        return stored
    }

    private static func restore(_ stored: StoredKey) throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw Failure.unavailable }
        let key: SecureEnclave.P256.Signing.PrivateKey
        do { key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored.wrappedKey) }
        catch { throw Failure.invalidStoredKey }
        try validate(stored.identity, publicKey: key.publicKey)
        return key
    }

    private static func validate(_ identity: Identity, publicKey: P256.Signing.PublicKey) throws {
        _ = try query(keyId: identity.keyId)
        guard identity.algorithm == "ecdsa_p256_sha256",
              identity.protectionClass == "os_protected_nonextractable",
              let der = Data(base64Encoded: identity.publicKeySpkiDerBase64),
              der.base64EncodedString() == identity.publicKeySpkiDerBase64,
              let parsed = try? P256.Signing.PublicKey(derRepresentation: der),
              parsed.derRepresentation == der, publicKey.derRepresentation == der else {
            throw Failure.invalidIdentity
        }
    }
}
