import Foundation

// This protocol contains no credentials and is never decoded by the demo engine.
struct LiveBinding: Codable, Equatable, Sendable {
    let accountID: String
    let controllerID: String
    let environmentID: String
    let sessionID: String
    func validate() throws {
        for value in [accountID, controllerID, environmentID, sessionID] {
            guard !value.isEmpty, value.utf8.count <= 512, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LiveWireError.invalid }
        }
    }
}
struct LiveSnapshot: Codable, Equatable, Sendable {
    let binding: LiveBinding?
    let generatedAt: Date
    let hostName: String
    let threads: [RemoteThread]
    let connected: Bool
    init(binding: LiveBinding?, generatedAt: Date = Date(), hostName: String, threads: [RemoteThread], connected: Bool) {
        self.binding = binding; self.generatedAt = generatedAt; self.hostName = hostName
        self.threads = threads; self.connected = connected
    }
    static func empty() -> Self { .init(binding: nil, hostName: "未连接", threads: [], connected: false) }
    func validate() throws {
        if let binding { try binding.validate() }
        guard hostName.utf8.count <= 1024 else { throw LiveWireError.invalid }
        for thread in threads {
            if let turnID = thread.currentTurnID {
                guard !turnID.isEmpty, turnID.utf8.count <= 512,
                      !turnID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LiveWireError.invalid }
            }
            guard !thread.id.isEmpty, thread.id.utf8.count <= 512,
                  !thread.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  thread.title.utf8.count <= 1024, thread.project.utf8.count <= 2048,
                  thread.summary.utf8.count <= 8192 else { throw LiveWireError.invalid }
        }
        guard !connected || binding != nil, threads.count <= 20,
              Set(threads.map(\.id)).count == threads.count,
              generatedAt.timeIntervalSinceNow <= 5 else { throw LiveWireError.invalid }
    }
    var fresh: Bool { connected && binding != nil && Date().timeIntervalSince(generatedAt) >= -5 && Date().timeIntervalSince(generatedAt) < 120 }
}
struct LiveCommand: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case refresh, read, sendText, interrupt }
    let id: UUID
    let issuedAt: Date
    let binding: LiveBinding
    let kind: Kind
    let threadID: String?
    let text: String?
    let turnID: String?
    init(id: UUID = UUID(), issuedAt: Date = Date(), binding: LiveBinding, kind: Kind, threadID: String? = nil, text: String? = nil, turnID: String? = nil) {
        self.id = id; self.issuedAt = issuedAt; self.binding = binding; self.kind = kind
        self.threadID = threadID; self.text = text; self.turnID = turnID
    }
    var isMutation: Bool { kind == .sendText || kind == .interrupt }
    func validate(now: Date = Date()) throws {
        try binding.validate()
        guard now.timeIntervalSince(issuedAt) >= -5, now.timeIntervalSince(issuedAt) <= 30 else { throw LiveWireError.stale }
        switch kind {
        case .refresh: guard threadID == nil, text == nil, turnID == nil else { throw LiveWireError.invalid }
        case .read: guard text == nil, turnID == nil else { throw LiveWireError.invalid }
        case .sendText: guard turnID == nil else { throw LiveWireError.invalid }
        case .interrupt: guard text == nil else { throw LiveWireError.invalid }
        }
        if kind != .refresh { guard let threadID, !threadID.isEmpty, threadID.utf8.count <= 512, !threadID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LiveWireError.invalid } }
        if kind == .sendText { guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else { throw LiveWireError.invalid } }
        if kind == .interrupt { guard let turnID, !turnID.isEmpty, turnID.utf8.count <= 512, !turnID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw LiveWireError.invalid } }
    }
}
struct LiveReply: Codable, Sendable {
    enum State: String, Codable, Sendable { case succeeded, rejected, unknown }
    let requestID: UUID
    let state: State
    let detail: String
    let snapshot: LiveSnapshot
}
enum LiveWireError: Error, LocalizedError {
    case invalid, stale, unreachable
    var errorDescription: String? {
        switch self {
        case .invalid: return "真实连接消息无效，已拒绝。"
        case .stale: return "确认信息已过期，请刷新后重新核对。"
        case .unreachable: return "iPhone 不可达；未发送，不会排队或重试。"
        }
    }
}
enum LiveWire {
    static let key = "codex.remote.live.v1"
    private struct Envelope<T: Codable>: Codable { let mode: String; let version: Int; let value: T }
    static func encode<T: Codable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(mode: "live", version: 1, value: value))
        guard data.count <= 60_000 else { throw LiveWireError.invalid }; return data
    }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= 60_000 else { throw LiveWireError.invalid }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.mode == "live", envelope.version == 1 else { throw LiveWireError.invalid }
        return envelope.value
    }
}
