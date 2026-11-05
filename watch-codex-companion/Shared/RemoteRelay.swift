import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RemoteRelayError: Error, Equatable, Sendable {
    case invalidInput, malformedFrame, frameTooLarge, chunksUnsupported
    case wrongDestination, sequenceGap, disconnected, busy, notInitialized
    case timedOut, outcomeUnknown(requestID: Int), remoteFailure, unsupportedMethod
}

/// Pure relay-v3 framing. No credentials, networking, thread creation, or mutations.
public struct RemoteRelayCodec {
    public static let maximumFrameBytes = 150 * 1024
    public static let maximumSafeInteger = 9_007_199_254_740_991
    public let clientID: String
    public let environmentID: String
    public let streamID: String
    public private(set) var nextSequence = 1
    public private(set) var lastServerSequence: Int?
    public private(set) var pendingID: Int?

    public init(clientID: String, environmentID: String, streamID: String = UUID().uuidString) throws {
        guard [clientID, environmentID, streamID].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 512 }) else {
            throw RemoteRelayError.invalidInput
        }
        self.clientID = clientID; self.environmentID = environmentID; self.streamID = streamID
    }

    public static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumFrameBytes else { throw RemoteRelayError.frameTooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteRelayError.malformedFrame
        }
        return object
    }

    public static func request(id: Int, method: String, cursor: String? = nil, threadID: String? = nil) throws -> Data {
        guard id > 0, id <= maximumSafeInteger else { throw RemoteRelayError.invalidInput }
        let params: [String: Any]
        switch method {
        case "initialize":
            params = ["clientInfo": ["name": "watch_codex_companion", "title": NSNull(), "version": "0.1.0"], "capabilities": NSNull()]
        case "thread/list":
            guard (cursor?.utf8.count ?? 0) <= 4096 else { throw RemoteRelayError.invalidInput }
            params = ["limit": 20, "cursor": cursor as Any? ?? NSNull(), "currentAccountOnly": true]
        case "thread/read":
            guard let threadID, !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, threadID.utf8.count <= 512 else { throw RemoteRelayError.invalidInput }
            params = ["threadId": threadID, "includeTurns": false]
        default: throw RemoteRelayError.unsupportedMethod
        }
        return try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
    }

    public mutating func envelope(_ message: Data) throws -> Data {
        let body = try Self.object(message)
        guard nextSequence <= Self.maximumSafeInteger else { throw RemoteRelayError.invalidInput }
        let id = try body["id"].map { try Self.integer($0) }
        if id != nil && pendingID != nil { throw RemoteRelayError.busy }
        let frame = try JSONSerialization.data(withJSONObject: [
            "type": "client_message", "client_id": clientID, "env_id": environmentID,
            "stream_id": streamID, "seq_id": nextSequence, "skip_history": false, "message": body
        ])
        guard frame.count <= Self.maximumFrameBytes else { throw RemoteRelayError.frameTooLarge }
        nextSequence += 1
        if let id { pendingID = id }
        return frame
    }

    /// Returns only the correlated response. ACKs never resolve a request.
    /// ponytail: single in-flight read avoids ambiguous un-IDed relay errors.
    public mutating func receive(_ data: Data) throws -> Data? {
        let frame = try Self.object(data)
        guard let type = frame["type"] as? String else { throw RemoteRelayError.malformedFrame }
        guard type == "server_message" || type == "server_message_chunk" else {
            if type == "error" { throw RemoteRelayError.remoteFailure }
            return nil
        }
        guard frame["client_id"] as? String == clientID, frame["env_id"] as? String == environmentID else {
            throw RemoteRelayError.wrongDestination
        }
        guard let stream = frame["stream_id"] as? String else { throw RemoteRelayError.malformedFrame }
        guard stream == streamID else { return nil }
        // Reject before decoding base64 or allocating any reassembly storage.
        guard type != "server_message_chunk" else { throw RemoteRelayError.chunksUnsupported }
        let sequence = try Self.integer(frame["seq_id"])
        if let lastServerSequence {
            if sequence <= lastServerSequence { return nil }
            guard sequence == lastServerSequence + 1 else { throw RemoteRelayError.sequenceGap }
        }
        guard var message = frame["message"] as? [String: Any] else { throw RemoteRelayError.malformedFrame }
        lastServerSequence = sequence
        if message["type"] as? String == "error", message["id"] == nil {
            guard let pendingID else { throw RemoteRelayError.remoteFailure }
            message.removeValue(forKey: "type")
            message = ["id": pendingID, "error": message]
        }
        // Notifications and host-initiated requests are not read results.
        guard message["method"] == nil, let rawID = message["id"], let pendingID else { return nil }
        guard try Self.integer(rawID) == pendingID else { return nil }
        guard (message["result"] != nil) != (message["error"] != nil) else { throw RemoteRelayError.malformedFrame }
        self.pendingID = nil
        return try JSONSerialization.data(withJSONObject: message)
    }

    static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= Double(maximumSafeInteger),
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { throw RemoteRelayError.malformedFrame }
        return number.intValue
    }
}

/// Explicitly injected authorization only. The application must supply an approved
/// OAuth integration, enrolled identity and authorized signer; this type obtains none.
public actor RemoteRelay {
    public typealias Signer = @Sendable (Data) async throws -> Data
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reader: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var codec: RemoteRelayCodec?
    private var pending: CheckedContinuation<Data, Error>?
    private var pendingID: Int?
    private var nextID = 1
    private var initialized = false
    private var connecting = false

    public init() {}

    public func connect(accessToken: String, accountID: String, record: RemoteEnrollmentRecord,
                        session authorization: RemoteControlSession, environmentID: String,
                        signer: @escaping Signer) async throws {
        guard socket == nil, !connecting else { throw RemoteRelayError.busy }
        let now = Int64(Date().timeIntervalSince1970)
        _ = try RemoteSigning.validateSession(record: record, session: authorization, nowEpoch: now)
        guard [accessToken, accountID, record.clientId, authorization.remoteControlToken].allSatisfy(Self.headerSafe) else {
            throw RemoteRelayError.invalidInput
        }
        let newCodec = try RemoteRelayCodec(clientID: record.clientId, environmentID: environmentID)
        var request = URLRequest(url: URL(string: "wss://chatgpt.com/backend-api/codex/remote/control/client")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(record.clientId, forHTTPHeaderField: "x-codex-client-id")
        request.setValue("3", forHTTPHeaderField: "x-codex-protocol-version")
        request.setValue("Bearer \(authorization.remoteControlToken)", forHTTPHeaderField: "x-codex-client-session-token")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: RemoteRelayRedirectGuard(), delegateQueue: nil)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = RemoteRelayCodec.maximumFrameBytes
        self.session = session; self.socket = socket; self.codec = newCodec; connecting = true
        socket.resume()
        // Cancellation closes the actual socket, unblocking receive/send on timeout.
        let handshakeTimer = Task {
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { handshakeTimer.cancel(); connecting = false }
        do {
            let challengeData = try Self.data(await socket.receive())
            guard try RemoteRelayCodec.object(challengeData)["type"] as? String == "device_key_challenge" else { throw RemoteRelayError.malformedFrame }
            let challenge = try JSONDecoder().decode(RemoteConnectionChallenge.self, from: challengeData)
            let payload = try RemoteSigning.connectionPayload(record: record, session: authorization, challenge: challenge,
                                                               nowEpoch: Int64(Date().timeIntervalSince1970))
            let signature = try await signer(payload)
            guard !signature.isEmpty, signature.count <= 80, self.socket === socket else { throw RemoteRelayError.disconnected }
            _ = try RemoteSigning.validateSession(record: record, session: authorization, nowEpoch: Int64(Date().timeIntervalSince1970))
            let proof = try JSONSerialization.data(withJSONObject: ["type": "device_key_proof", "keyId": record.keyId,
                "signatureDerBase64": signature.base64EncodedString(), "signedPayloadBase64": payload.base64EncodedString(), "algorithm": record.algorithm])
            try await socket.send(.string(String(decoding: proof, as: UTF8.self)))
            reader = Task { [weak self] in
                guard let self else { return }
                await self.receiveLoop(socket)
            }
            _ = try await rpc(method: "initialize")
            guard var codec = self.codec else { throw RemoteRelayError.disconnected }
            let notification = try codec.envelope(Data(#"{"method":"initialized"}"#.utf8))
            self.codec = codec
            try await socket.send(.string(String(decoding: notification, as: UTF8.self)))
            guard self.socket === socket else { throw RemoteRelayError.disconnected }
            initialized = true
        } catch {
            disconnect()
            throw error
        }
    }

    public func listThreads(cursor: String? = nil) async throws -> Data {
        guard initialized else { throw RemoteRelayError.notInitialized }
        return try await rpc(method: "thread/list", cursor: cursor)
    }

    public func readThread(id: String) async throws -> Data {
        guard initialized else { throw RemoteRelayError.notInitialized }
        return try await rpc(method: "thread/read", threadID: id)
    }

    public func disconnect() {
        fail(RemoteRelayError.disconnected)
    }

    private func rpc(method: String, cursor: String? = nil, threadID: String? = nil) async throws -> Data {
        guard let socket, var codec else { throw RemoteRelayError.disconnected }
        guard pending == nil else { throw RemoteRelayError.busy }
        guard nextID <= RemoteRelayCodec.maximumSafeInteger else { throw RemoteRelayError.invalidInput }
        let id = nextID; nextID += 1
        let frame = try codec.envelope(RemoteRelayCodec.request(id: id, method: method, cursor: cursor, threadID: threadID))
        self.codec = codec
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation; pendingID = id
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                    await self?.expire(id)
                }
                Task { [weak self] in
                    do { try await socket.send(.string(String(decoding: frame, as: UTF8.self))) }
                    catch { await self?.sendFailed(id) }
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func expire(_ id: Int) { if pendingID == id { fail(RemoteRelayError.timedOut) } }
    private func sendFailed(_ id: Int) { if pendingID == id { fail(RemoteRelayError.disconnected) } }
    private func cancelRequest(_ id: Int) { if pendingID == id { fail(CancellationError()) } }

    private func receiveLoop(_ activeSocket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let data = try Self.data(await activeSocket.receive())
                guard socket === activeSocket, var codec else { return }
                let response = try codec.receive(data)
                self.codec = codec
                if let response, let pending {
                    timeout?.cancel(); timeout = nil
                    self.pending = nil; pendingID = nil
                    let message = try RemoteRelayCodec.object(response)
                    if message["error"] != nil { pending.resume(throwing: RemoteRelayError.remoteFailure) }
                    else { pending.resume(returning: response) }
                }
            }
        } catch {
            if socket === activeSocket { fail(error) }
        }
    }

    private func fail(_ error: Error) {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        reader?.cancel(); reader = nil; timeout?.cancel(); timeout = nil
        initialized = false; codec = nil
        // A socket failure or timeout cannot prove whether a dispatched request ran.
        if let pending {
            let reported: Error
            if error as? RemoteRelayError == .chunksUnsupported || error as? RemoteRelayError == .frameTooLarge {
                reported = error
            } else { reported = RemoteRelayError.outcomeUnknown(requestID: pendingID ?? 0) }
            pending.resume(throwing: reported)
        }
        pending = nil; pendingID = nil
    }

    private static func data(_ message: URLSessionWebSocketTask.Message) throws -> Data {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw RemoteRelayError.malformedFrame
        }
        guard data.count <= RemoteRelayCodec.maximumFrameBytes else { throw RemoteRelayError.frameTooLarge }
        return data
    }

    private static func headerSafe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32_768 && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }
}

// Never forward bearer/session headers through a redirect to another endpoint.
private final class RemoteRelayRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
