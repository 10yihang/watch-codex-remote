import Foundation
import Security

/// Device-only recovery state. No bearer tokens or pairing codes are stored here.
struct RemoteConnectionJournal: Codable {
    enum Phase: String, Codable { case authorizing, enrollmentUnknown, enrolled, pairingUnknown, paired, revocationUnknown }
    struct Mutation: Codable {
        let id: UUID
        let threadID: String
        let environmentID: String
        let turnID: String?
        let kind: LiveCommand.Kind
    }
    var accountID: String
    var record: RemoteEnrollmentRecord
    var phase: Phase
    var environmentID: String?
    var pendingMutation: Mutation?
    var recentRequestIDs: [UUID] = []

    private static let service = "com.watchcodex.companion.remote-journal.v1"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "controller",
         kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    }
    static func load() throws -> Self? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item = result as? [String: Any],
              item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
              let data = item[kSecValueData as String] as? Data, data.count <= 65_536 else {
            throw RemoteConnectionError.storage
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.recentRequestIDs.count <= 100 else { throw RemoteConnectionError.storage }
        return value
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 65_536, recentRequestIDs.count <= 100 else { throw RemoteConnectionError.storage }
        let changes = [kSecValueData as String: data,
                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(Self.query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = Self.query
            changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RemoteConnectionError.storage }
        } else if status != errSecSuccess { throw RemoteConnectionError.storage }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RemoteConnectionError.storage }
    }
}

enum RemoteConnectionError: Error, LocalizedError {
    case storage, signInRequired, enrollmentRequired, recoveryRequired, hostUnavailable, stale, busy, foreground, malformedResult
    var errorDescription: String? {
        switch self {
        case .storage: return "无法安全保存或读取本机连接状态；没有继续操作。"
        case .signInRequired: return "请先在此 iPhone 登录或恢复登录。"
        case .enrollmentRequired: return "请先明确授权注册此 iPhone。"
        case .recoveryRequired: return "上次操作需要核对；不会自动重试、删除密钥或新建会话。"
        case .hostUnavailable: return "选定主机不在最新在线列表中。"
        case .stale: return "连接或会话状态已变化，请刷新并重新确认。"
        case .busy: return "已有请求正在处理。"
        case .foreground: return "请保持 iPhone App 在前台并解锁后操作。"
        case .malformedResult: return "主机返回的结果无法匹配当前会话。"
        }
    }
}
