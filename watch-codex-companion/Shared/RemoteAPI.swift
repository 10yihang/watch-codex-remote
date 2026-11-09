import Foundation

// Observed rcodex contract, not a provider-approved iOS authorization mechanism.
// Values come only from the explicit native experimental OAuth flow.
// There is deliberately no paste/import/desktop credential path in this app.
struct RemoteAccountAuthorization {
    let accessToken: String
    let accountID: String
    let accountUserID: String
    var tokenUserID: String? = nil
    func accepts(_ value: String) -> Bool { value == accountUserID || value == tokenUserID }

    func validate() throws {
        for value in [accessToken, accountID, accountUserID] + [tokenUserID].compactMap({ $0 }) {
            guard !value.isEmpty, value.utf8.count <= 16_384,
                  value.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
                throw RemoteAPIError.invalidInput
            }
        }
    }
}

enum RemoteAPIError: Error, LocalizedError, Equatable {
    case invalidInput, invalidResponse, responseTooLarge, accountMismatch
    case httpStatus(Int)
    case outcomeUnknown
    case timedOut, cancelled, transportFailed

    var errorDescription: String? {
        switch self {
        case .timedOut: return "读取 Remote 响应超时；未自动重试。"
        case .cancelled: return "Remote 读取已取消。"
        case .transportFailed: return "Remote 网络连接失败；未自动重试。"
        case .invalidInput: return "Remote 请求参数无效。"
        case .invalidResponse: return "Remote 返回了无法验证的响应。"
        case .responseTooLarge: return "Remote 响应超出本版本的大小上限。"
        case .accountMismatch: return "Remote 返回的账号或控制器不匹配。"
        case .httpStatus(let code): return "Remote 请求失败（HTTP \(code)）。"
        case .outcomeUnknown: return "未能确认注册或配对结果。请先核对服务端状态，不要重复提交。"
        }
    }
}

struct RemoteEnrollmentStart: Decodable {
    let accountUserID: String
    let clientID: String
    let challenge: RemoteEnrollmentChallenge
    enum CodingKeys: String, CodingKey {
        case accountUserID = "account_user_id", clientID = "client_id"
        case challenge = "device_key_challenge"
    }
}

struct RemoteEnrollmentFinish: Decodable {
    let accountUserID: String
    let clientID: String
    let scopes: [String]
    enum CodingKeys: String, CodingKey {
        case accountUserID = "account_user_id", clientID = "client_id", scopes
    }
    func validate(record: RemoteEnrollmentRecord) throws {
        guard accountUserID == record.accountUserId, clientID == record.clientId,
              scopes == [RemoteSigning.sessionScope] else { throw RemoteAPIError.accountMismatch }
    }
}

struct RemoteHost: Decodable, Identifiable, Sendable {
    let envID: String
    let displayName: String?
    let hostName: String?
    let name: String?
    let online: Bool
    let busy: Bool
    let appServerVersion: String?
    var id: String { envID }
    var title: String {
        [displayName, name, hostName, envID].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? envID
    }
    enum CodingKeys: String, CodingKey {
        case envID = "env_id", displayName = "display_name", hostName = "host_name"
        case name, online, busy, appServerVersion = "app_server_version"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        envID = try values.decode(String.self, forKey: .envID)
        _ = try RemoteAPI.pathID(envID)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
        hostName = try values.decodeIfPresent(String.self, forKey: .hostName)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        online = try values.decodeIfPresent(Bool.self, forKey: .online) ?? false
        busy = try values.decodeIfPresent(Bool.self, forKey: .busy) ?? false
        appServerVersion = try values.decodeIfPresent(String.self, forKey: .appServerVersion)
    }
}

private struct RemoteHostPage: Decodable {
    let cursor: String?
    let items: [RemoteHost]
}

// Prevent redirecting Authorization headers, enrollment proofs or pairing codes.
private final class RemoteNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class RemoteAPI {
    static let baseURL = URL(string: "https://chatgpt.com/backend-api")!
    static let maxResponseBytes = 1_048_576
    private let authorization: RemoteAccountAuthorization
    private let session: URLSession

    init(authorization: RemoteAccountAuthorization) throws {
        try authorization.validate()
        self.authorization = authorization
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration, delegate: RemoteNoRedirect(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    // Each state-changing method is explicit. No auto-enroll, retry, fallback or
    // background work. A timeout may follow a successful server-side action.
    func startEnrollment() async throws -> RemoteEnrollmentStart {
        let start: RemoteEnrollmentStart = try await decode("POST", path: "/codex/remote/control/client/enroll/start", body: [:])
        do { try Self.validateEnrollmentStart(start, authorization: authorization, refresh: false, nowEpoch: Self.now) }
        catch { throw RemoteAPIError.outcomeUnknown }
        return start
    }

    func finishEnrollment(record: RemoteEnrollmentRecord, stepUpToken: String,
                          proof: RemoteDeviceKeyProof) async throws -> RemoteEnrollmentFinish {
        guard authorization.accepts(record.accountUserId),
              !stepUpToken.isEmpty, stepUpToken.utf8.count <= 16_384,
              !stepUpToken.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw RemoteAPIError.invalidInput
        }
        let identity: [String: Any] = [
            "key_id": record.keyId, "algorithm": record.algorithm,
            "protection_class": record.protectionClass,
            "public_key_spki_der_base64": record.publicKeySpkiDerBase64
        ]
        let result: RemoteEnrollmentFinish = try await decode("POST", path: "/codex/remote/control/client/enroll/finish", body: [
            "client_id": record.clientId, "step_up_token": stepUpToken,
            "device_identity": identity, "device_key_proof": try encodedObject(proof)
        ])
        do { try result.validate(record: record) }
        catch { throw RemoteAPIError.outcomeUnknown }
        return result
    }

    func startRefresh(record: RemoteEnrollmentRecord) async throws -> RemoteEnrollmentStart {
        guard authorization.accepts(record.accountUserId) else { throw RemoteAPIError.accountMismatch }
        let start: RemoteEnrollmentStart = try await decode("POST", path: "/codex/remote/control/client/refresh/start", body: ["client_id": record.clientId])
        try Self.validateEnrollmentStart(start, authorization: authorization, refresh: true, nowEpoch: Self.now)
        guard start.clientID == record.clientId else { throw RemoteAPIError.accountMismatch }
        // This also validates the returned identity hash before any signing.
        _ = try RemoteSigning.enrollmentPayload(record: record, challenge: start.challenge, refresh: true, nowEpoch: Self.now)
        return start
    }

    func finishRefresh(record: RemoteEnrollmentRecord, proof: RemoteDeviceKeyProof) async throws -> RemoteControlSession {
        guard authorization.accepts(record.accountUserId) else { throw RemoteAPIError.accountMismatch }
        let result: RemoteControlSession = try await decode("POST", path: "/codex/remote/control/client/refresh/finish", body: [
            "client_id": record.clientId, "device_key_proof": try encodedObject(proof)
        ])
        do { _ = try RemoteSigning.validateSession(record: record, session: result, nowEpoch: Self.now) }
        catch { throw RemoteAPIError.outcomeUnknown }
        return result
    }

    func pair(clientID: String, code: String) async throws {
        _ = try await request("POST", path: "/wham/remote/control/client/pair", body: Self.pairingBody(clientID: clientID, code: code))
    }

    func revoke(clientID: String) async throws {
        // Caller removes its device key only after confirmed revocation.
        _ = try await request("DELETE", path: "/wham/remote/control/clients/" + Self.pathID(clientID), allowNotFound: true)
    }

    func hosts(clientID: String) async throws -> [RemoteHost] {
        let path = "/codex/remote/control/clients/" + (try Self.pathID(clientID)) + "/environments"
        var items = [RemoteHost](), seenCursors = Set<String>(), seenIDs = Set<String>()
        var cursor: String?
        repeat {
            let query = [URLQueryItem(name: "limit", value: "100")] + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            let data = try await request("GET", path: path, query: query)
            let page = try JSONDecoder().decode(RemoteHostPage.self, from: data)
            guard items.count + page.items.count <= 100 else { throw RemoteAPIError.responseTooLarge }
            for host in page.items {
                _ = try Self.pathID(host.envID)
                guard seenIDs.insert(host.envID).inserted else { throw RemoteAPIError.invalidResponse }
            }
            items += page.items
            cursor = page.cursor
            if let cursor {
                guard !cursor.isEmpty, cursor.utf8.count <= 1024,
                      !cursor.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      seenCursors.count < 32, seenCursors.insert(cursor).inserted, items.count < 100 else {
                    throw RemoteAPIError.invalidResponse
                }
            }
        } while cursor != nil
        return items
    }

    static func pairingBody(clientID: String, code: String) throws -> [String: String] {
        _ = try pathID(clientID)
        let compact = code.utf8.filter { ![9, 10, 11, 12, 13, 32, 45].contains($0) }
        guard compact.count == 8, compact.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw RemoteAPIError.invalidInput
        }
        let letters = String(decoding: compact, as: UTF8.self).uppercased()
        let split = letters.index(letters.startIndex, offsetBy: 4)
        return ["client_id": clientID, "manual_pairing_code": String(letters[..<split]) + "-" + String(letters[split...])]
    }

    static func pathID(_ value: String) throws -> String {
        // Reject ambiguous path syntax rather than normalizing it into another ID.
        guard !value.isEmpty, value.utf8.count <= 256,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw RemoteAPIError.invalidInput
        }
        return value
    }

    static func failureAfterDispatch(_ error: Error, method: String) -> RemoteAPIError {
        if method == "GET" {
            if let error = error as? RemoteAPIError { return error }
            if error is CancellationError { return .cancelled }
            if let error = error as? URLError {
                switch error.code {
                case .cancelled: return .cancelled
                case .timedOut: return .timedOut
                default: return .transportFailed
                }
            }
            return .invalidResponse
        }
        // An explicit client-side rejection is different from a timeout, 5xx,
        // corrupt/oversized success response or failure to validate a new session.
        if let apiError = error as? RemoteAPIError, case .httpStatus(let status) = apiError,
           (400...499).contains(status), status != 408 { return .httpStatus(status) }
        return .outcomeUnknown
    }

    static func validateEnrollmentStart(_ start: RemoteEnrollmentStart, authorization: RemoteAccountAuthorization,
                                        refresh: Bool, nowEpoch: Int64) throws {
        try authorization.validate()
        guard authorization.accepts(start.accountUserID),
              start.challenge.accountUserId == start.accountUserID,
              start.challenge.clientId == start.clientID else { throw RemoteAPIError.accountMismatch }
        let challenge = start.challenge
        guard challenge.challengeExpiresAt > nowEpoch,
              challenge.purpose == "remote_control_client_enrollment",
              challenge.audience == "remote_control_client_enrollment",
              challenge.targetOrigin == "https://chatgpt.com",
              challenge.targetPath == "/backend-api/codex/remote/control/client/" + (refresh ? "refresh/finish" : "enroll/finish"),
              !challenge.challengeId.isEmpty, !challenge.challengeToken.isEmpty else {
            throw RemoteAPIError.invalidResponse
        }
        _ = try Self.pathID(start.clientID)
    }

    private static var now: Int64 { Int64(Date().timeIntervalSince1970) }

    private func encodedObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func decode<T: Decodable>(_ method: String, path: String, body: [String: Any]) async throws -> T {
        let data = try await request(method, path: path, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw method == "GET" ? RemoteAPIError.invalidResponse : RemoteAPIError.outcomeUnknown }
    }

    private func request(_ method: String, path: String, query: [URLQueryItem] = [],
                         body: [String: Any]? = nil, allowNotFound: Bool = false) async throws -> Data {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.path += path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url, url.scheme == "https", url.host == "chatgpt.com",
              url.user == nil, url.password == nil, url.port == nil else { throw RemoteAPIError.invalidInput }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer " + authorization.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(authorization.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("watch-codex-companion/0.2-experimental", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw RemoteAPIError.invalidResponse }
            guard (200...299).contains(response.statusCode) || (allowNotFound && response.statusCode == 404) else {
                throw RemoteAPIError.httpStatus(response.statusCode)
            }
            guard response.expectedContentLength <= Int64(Self.maxResponseBytes) else { throw RemoteAPIError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maxResponseBytes else { throw RemoteAPIError.responseTooLarge }
                data.append(byte)
            }
            return data
        } catch {
            // No token, response body, code or underlying URL error in diagnostics.
            throw Self.failureAfterDispatch(error, method: method)
        }
    }
}
