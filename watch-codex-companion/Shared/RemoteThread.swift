import Foundation
import CoreFoundation

/// Runtime state is server evidence, not the phone's connection or loading state.
public enum RemoteThreadState: String, Codable, Sendable {
    case running, ready, interrupted, failed, notLoaded, unknown
    public var label: String {
        switch self {
        case .running: return "运行中"
        case .ready: return "空闲"
        case .interrupted: return "已中断"
        case .failed: return "错误"
        case .notLoaded: return "尚未载入"
        case .unknown: return "未知状态"
        }
    }
}

public struct RemoteThreadPage: Equatable, Sendable {
    public let threads: [RemoteThread]
    public let nextCursor: String?
}

/// Bounded projection of app-server v2 Thread/Turn responses. No demo defaults.
public struct RemoteThread: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let state: RemoteThreadState
    public let summary: String
    public let currentTurnID: String?
    public let updatedAt: Date

    #if !os(watchOS)
    public static func decodePage(_ data: Data) throws -> RemoteThreadPage {
        let result = try resultObject(data)
        guard let rows = result["data"] as? [[String: Any]], rows.count <= 20 else { throw RemoteRelayError.malformedFrame }
        let threads = try rows.map(parse)
        guard Set(threads.map(\.id)).count == threads.count else { throw RemoteRelayError.malformedFrame }
        let cursor = try optionalString(result["nextCursor"], limit: 4096)
        return RemoteThreadPage(threads: threads, nextCursor: cursor)
    }

    public static func decodeRead(_ data: Data, expectedThreadID: String) throws -> RemoteThread {
        let result = try resultObject(data)
        guard let object = result["thread"] as? [String: Any] else { throw RemoteRelayError.malformedFrame }
        let thread = try parse(object)
        guard thread.id == expectedThreadID else { throw RemoteRelayError.staleSelection }
        return thread
    }

    public static func decodeStartedTurn(_ data: Data) throws -> String {
        let result = try resultObject(data)
        guard let turn = result["turn"] as? [String: Any], let id = turn["id"] as? String,
              RemoteRelayCodec.validIdentifier(id) else { throw RemoteRelayError.malformedFrame }
        return id
    }

    private static func resultObject(_ data: Data) throws -> [String: Any] {
        let response = try RemoteRelayCodec.object(data)
        guard response["error"] == nil else { throw RemoteRelayError.remoteFailure }
        guard let result = response["result"] as? [String: Any] else { throw RemoteRelayError.malformedFrame }
        return result
    }

    private static func optionalString(_ raw: Any?, limit: Int) throws -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let value = raw as? String, value.utf8.count <= limit else { throw RemoteRelayError.malformedFrame }
        return value
    }

    private static func parse(_ object: [String: Any]) throws -> RemoteThread {
        guard let id = object["id"] as? String, RemoteRelayCodec.validIdentifier(id),
              let preview = object["preview"] as? String,
              let cwd = object["cwd"] as? String,
              let timestamp = object["updatedAt"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID(), timestamp.doubleValue.isFinite,
              timestamp.doubleValue >= 0, timestamp.doubleValue <= 253_402_300_799,
              let turns = object["turns"] as? [[String: Any]],
              let status = object["status"] as? [String: Any], let kind = status["type"] as? String
        else { throw RemoteRelayError.malformedFrame }
        let name = try optionalString(object["name"], limit: 16_384)
        var activeID: String?
        var lastStatus: String?
        var summary = preview
        var seen = Set<String>()
        for turn in turns {
            guard let turnID = turn["id"] as? String, RemoteRelayCodec.validIdentifier(turnID), seen.insert(turnID).inserted,
                  let turnStatus = turn["status"] as? String,
                  ["inProgress", "completed", "interrupted", "failed"].contains(turnStatus),
                  let items = turn["items"] as? [[String: Any]] else { throw RemoteRelayError.malformedFrame }
            if turnStatus == "inProgress" {
                guard activeID == nil else { throw RemoteRelayError.malformedFrame }
                activeID = turnID
            }
            lastStatus = turnStatus
            for item in items where item["type"] as? String == "agentMessage" {
                if let text = item["text"] as? String, !text.isEmpty { summary = text }
            }
            if let error = turn["error"] as? [String: Any], let message = error["message"] as? String { summary = message }
        }
        let state: RemoteThreadState
        switch kind {
        case "active": state = .running
        case "systemError": state = .failed; activeID = nil
        case "notLoaded": state = .notLoaded; activeID = nil
        case "idle":
            // Conflicting stale turn history must never offer an interrupt target.
            guard activeID == nil else { throw RemoteRelayError.malformedFrame }
            state = lastStatus == "failed" ? .failed : lastStatus == "interrupted" ? .interrupted : .ready
        default: state = .unknown; activeID = nil
        }
        return RemoteThread(id: id, title: String((name.flatMap { $0.isEmpty ? nil : $0 } ?? (preview.isEmpty ? id : preview)).prefix(200)),
                            project: String(cwd.prefix(200)), state: state, summary: String(summary.prefix(2200)),
                            currentTurnID: activeID, updatedAt: Date(timeIntervalSince1970: timestamp.doubleValue))
    }
    #endif
}
