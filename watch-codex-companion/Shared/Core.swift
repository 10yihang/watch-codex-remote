import Foundation

// This is the phone/watch DEMO wire contract, not the Codex Remote protocol.
public enum RunState: String, Codable, Sendable {
    case running, ready, interrupted
    public var label: String {
        switch self { case .running: return "演示运行中"; case .ready: return "演示就绪"; case .interrupted: return "演示已停止" }
    }
    public var symbol: String {
        switch self { case .running: return "waveform"; case .ready: return "checkmark.circle"; case .interrupted: return "stop.circle" }
    }
}

public struct ThreadSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var project: String
    public var state: RunState
    public var summary: String
    public var currentTurnID: String?
    public var updatedAt: Date
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var source = "demo"
    public var remoteConnected = false
    public var generatedAt: Date
    public var threads: [ThreadSummary]

    public static func empty(now: Date = Date()) -> Snapshot {
        Snapshot(generatedAt: now, threads: [])
    }
    public static func sample(now: Date = Date()) -> Snapshot {
        Snapshot(generatedAt: now, threads: [
            ThreadSummary(id: "demo-existing-thread-01", title: "收好最后一处细节", project: "Watch companion", state: .running,
                          summary: "正在检查输入、断连和重复点击。这里是示例进度，不代表真实主机。", currentTurnID: "demo-turn-01", updatedAt: now),
            ThreadSummary(id: "demo-existing-thread-02", title: "让状态一眼看懂", project: "Interface", state: .ready,
                          summary: "三个层次：手表到手机、手机到 Remote、任务执行。当前只体验演示数据。", currentTurnID: nil, updatedAt: now.addingTimeInterval(-180)),
            ThreadSummary(id: "demo-existing-thread-03", title: "复用已有会话", project: "Protocol", state: .ready,
                          summary: "保留已有 thread 标识。不创建、不 fork，也不替换权限或工作目录。", currentTurnID: nil, updatedAt: now.addingTimeInterval(-900))
        ])
    }
    public func validate(now: Date = Date()) throws {
        guard version == 1, source == "demo", remoteConnected == false else { throw WireError.invalid("不支持的快照来源或版本") }
        guard generatedAt.timeIntervalSince(now) <= 30, threads.count <= 20,
              Set(threads.map(\.id)).count == threads.count else { throw WireError.invalid("快照时间、数量或会话标识无效") }
        for thread in threads {
            guard thread.id.hasPrefix("demo-"), thread.id.utf8.count <= 128,
                  !thread.title.isEmpty, thread.title.count <= 200, thread.project.count <= 200,
                  thread.summary.count <= 2_200, thread.updatedAt.timeIntervalSince(now) <= 30,
                  (thread.state == .running) == (thread.currentTurnID != nil),
                  thread.currentTurnID.map({ $0.hasPrefix("demo-") && $0.utf8.count <= 128 }) ?? true
            else { throw WireError.invalid("快照内容不符合演示约束") }
        }
    }
}

public enum CommandKind: String, Codable, Sendable { case refresh, sendText, interrupt }
public struct Command: Codable, Equatable, Sendable {
    public var version = 1
    public var mode = "demo"
    public let id: UUID
    public let createdAt: Date
    public let kind: CommandKind
    public let threadID: String?
    public let turnID: String?
    public let text: String?

    public init(id: UUID = UUID(), createdAt: Date = Date(), kind: CommandKind,
                threadID: String? = nil, turnID: String? = nil, text: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.kind = kind
        self.threadID = threadID; self.turnID = turnID; self.text = text
    }
    public func validate(now: Date = Date()) throws {
        guard version == 1, mode == "demo" else { throw WireError.invalid("只接受演示命令") }
        let age = now.timeIntervalSince(createdAt)
        guard age >= -5, age < 30 else { throw WireError.invalid("请求已过期，请刷新后重试") }
        switch kind {
        case .refresh:
            guard threadID == nil, turnID == nil, text == nil else { throw WireError.invalid("刷新命令包含多余字段") }
        case .sendText:
            guard validID(threadID), turnID == nil, let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2_000
            else { throw WireError.invalid("请选择已有会话并输入 1–2000 字指令") }
        case .interrupt:
            guard validID(threadID), validID(turnID), text == nil else { throw WireError.invalid("停止需要明确的会话和 turn") }
        }
    }
    private func validID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.hasPrefix("demo-") && value.utf8.count <= 128
    }
}

public enum ReceiptState: String, Codable, Sendable { case demoApplied, rejected }
public struct Reply: Codable, Equatable, Sendable {
    public var version = 1
    public let requestID: UUID
    public let state: ReceiptState
    public let detail: String
    public let snapshot: Snapshot
}
public enum WireError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
public enum Wire {
    public static let key = "watchCodexDemoV1"
    public static let maximumBytes = 60 * 1024
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw WireError.invalid("消息过大，未发送") }
        return data
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumBytes else { throw WireError.invalid("消息过大，已拒绝") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

// No network, credentials, controller enrollment, or Remote execution lives here.
public struct DemoEngine {
    public private(set) var snapshot: Snapshot
    private var receipts: [UUID: (Command, Reply)] = [:]
    private var receiptOrder: [UUID] = []
    public init(now: Date = Date()) { snapshot = .sample(now: now) }

    public mutating func handle(_ command: Command, now: Date = Date()) -> Reply {
        if let (original, reply) = receipts[command.id] {
            guard original == command else { return reject(command, "重复请求标识的内容不一致") }
            return reply
        }
        do { try command.validate(now: now) }
        catch { return reject(command, error.localizedDescription) }
        var detail = "演示快照已刷新。Remote 尚未连接。"
        if command.kind != .refresh {
            guard let index = snapshot.threads.firstIndex(where: { $0.id == command.threadID }) else {
                return remember(command, reject(command, "找不到这个已有会话；不会另建会话"))
            }
            switch command.kind {
            case .sendText:
                guard snapshot.threads[index].state != .running else {
                    return remember(command, reject(command, "示例 turn 仍在运行，请先模拟停止"))
                }
                snapshot.threads[index].state = .running
                snapshot.threads[index].currentTurnID = "demo-turn-\(command.id.uuidString)"
                snapshot.threads[index].summary = "本地演示已接收：\(command.text!)\n没有发送到 Remote，也没有真实代码执行。"
                detail = "演示指令已应用。没有发送到 Remote。"
            case .interrupt:
                guard snapshot.threads[index].state == .running,
                      snapshot.threads[index].currentTurnID == command.turnID else {
                    return remember(command, reject(command, "turn 已变化，先刷新再决定；未停止其他任务"))
                }
                snapshot.threads[index].state = .interrupted
                snapshot.threads[index].currentTurnID = nil
                snapshot.threads[index].summary = "该示例 turn 已停止。真实 Remote 任务不受影响。"
                detail = "已模拟停止指定 turn。真实主机不受影响。"
            case .refresh: break
            }
            snapshot.threads[index].updatedAt = now
        }
        snapshot.generatedAt = now
        return remember(command, Reply(requestID: command.id, state: .demoApplied, detail: detail, snapshot: snapshot))
    }
    private func reject(_ command: Command, _ detail: String) -> Reply {
        Reply(requestID: command.id, state: .rejected, detail: detail, snapshot: snapshot)
    }
    private mutating func remember(_ command: Command, _ reply: Reply) -> Reply {
        receipts[command.id] = (command, reply); receiptOrder.append(command.id)
        // ponytail: bounded in-memory demo dedupe; real mutations need durable reconciliation, not auto-retry.
        if receiptOrder.count > 100 { receipts.removeValue(forKey: receiptOrder.removeFirst()) }
        return reply
    }
}
