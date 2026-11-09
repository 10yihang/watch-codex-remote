import Foundation
import SwiftUI
import UIKit

/// Foreground-only owner of the experimental native route. Construction performs
/// no network request, Keychain read/write, enrollment or automatic reconnect.
@MainActor
final class RemoteConnectionController: ObservableObject {
    @Published private(set) var snapshot = LiveSnapshot.empty()
    @Published private(set) var status = "尚未连接。实验性第三方协议，需要在真机验证。"
    @Published private(set) var busy = false
    @Published private(set) var signedIn = false
    @Published private(set) var enrolled = false
    @Published private(set) var hosts: [RemoteHost] = []
    @Published private(set) var selectedHostID: String?
    @Published private(set) var needsReview = false
    @Published private(set) var canRevoke = false
    @Published private(set) var reviewThreadID: String?
    @Published private(set) var reviewHostID: String?
    var onSnapshot: ((LiveSnapshot) -> Void)?
    private let oauth = CodexPlanOAuth()
    private let relay = RemoteRelay()
    private var account: RemoteAccountAuthorization?
    private var claims: RemoteAccountClaims?
    private var journal: RemoteConnectionJournal?
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var presenter: CodexOAuthSafariViewControllerPresenter?
    private var reviewedMutationID: UUID?
    private var reviewedBinding: LiveBinding?
    private var reviewedAt: Date?
    private var handlingID: UUID?
    private var teardown: Task<Void, Never>?
    private var connectionExpiry: Task<Void, Never>?

    func signIn() {
        run("正在打开 ChatGPT 登录…") {
            let existing = try RemoteConnectionJournal.load()
            let tokens = try await self.oauth.signIn(expectedAccountID: existing?.accountID,
                expectedAccountUserID: existing?.record.accountUserId, presentSafari: try self.presentation())
            try self.accept(tokens, matching: existing)
            if let existing {
                guard existing.accountID == self.claims?.accountID,
                      self.account?.accepts(existing.record.accountUserId) == true else { throw RemoteAPIError.accountMismatch }
                self.setJournal(existing)
            }
            self.status = "登录已完成，尚未连接主机。下一步单独授权注册此 iPhone。"
        }
    }

    func restore() {
        run("正在读取此 iPhone 的连接状态…") {
            let existing = try RemoteConnectionJournal.load()
            guard let tokens = try await self.oauth.storedTokens() else { throw RemoteConnectionError.signInRequired }
            do { try self.accept(tokens, matching: existing) }
            catch RemoteTokenClaimsError.expired { try self.accept(try await self.oauth.refreshStoredTokens(), matching: existing) }
            if let existing {
                guard existing.accountID == self.claims?.accountID,
                      self.account?.accepts(existing.record.accountUserId) == true else { throw RemoteAPIError.accountMismatch }
                self.setJournal(existing)
                if existing.phase != .revocationUnknown { _ = try RemoteDeviceKey.load(keyId: existing.record.keyId) }
                self.status = [.enrolled, .paired].contains(existing.phase)
                    ? "本机状态已恢复。请刷新主机列表并明确连接；不会自动重连。"
                    : "上次注册、配对或撤销结果需要核对。不会重复操作；可读取主机列表或撤销此控制器。"
            } else { self.status = "登录已恢复。此 iPhone 尚未注册为控制器。" }
        }
    }

    func enroll() {
        run("正在注册此 iPhone…") {
            guard self.journal == nil, try RemoteConnectionJournal.load() == nil else { throw RemoteConnectionError.recoveryRequired }
            let api = try self.api()
            guard let claims = self.claims else { throw RemoteConnectionError.signInRequired }
            let start = try await api.startEnrollment()
            try self.checkForeground()
            let identity = try RemoteDeviceKey.create()
            let record = RemoteEnrollmentRecord(accountUserId: start.accountUserID, algorithm: identity.algorithm,
                clientId: start.clientID, keyId: identity.keyId, protectionClass: identity.protectionClass,
                publicKeySpkiDerBase64: identity.publicKeySpkiDerBase64)
            var saved = RemoteConnectionJournal(accountID: claims.accountID, record: record, phase: .authorizing)
            do { try saved.save() } catch {
                // No finish request has been dispatched. Remove only this newly created key.
                try? RemoteDeviceKey.remove(keyId: record.keyId)
                throw error
            }
            self.setJournal(saved)
            let payload = try RemoteSigning.enrollmentPayload(record: record, challenge: start.challenge,
                refresh: false, nowEpoch: Self.now)
            let stepUp = try await self.oauth.stepUp(accountID: claims.accountID, accountUserID: claims.accountUserID,
                presentSafari: try self.presentation())
            try self.checkForeground()
            try stepUp.validate()
            let proof = try self.proof(record: record, challenge: start.challenge, payload: payload)
            // Persist unknown BEFORE dispatch. Process death cannot authorize a retry.
            saved.phase = .enrollmentUnknown; try saved.save(); self.setJournal(saved)
            _ = try await api.finishEnrollment(record: record, stepUpToken: stepUp.rawValue, proof: proof)
            saved.phase = .enrolled; try saved.save(); self.setJournal(saved)
            self.status = "此 iPhone 注册已获服务端确认。请在 Codex 桌面生成配对码。"
        }
    }

    func pair(code: String) {
        run("正在提交一次性配对码…") {
            var saved = try self.usableJournal(allowPairingUnknown: false)
            guard saved.phase == .enrolled || saved.phase == .paired else { throw RemoteConnectionError.recoveryRequired }
            _ = try RemoteAPI.pairingBody(clientID: saved.record.clientId, code: code)
            let api = try self.api()
            saved.phase = .pairingUnknown; try saved.save(); self.setJournal(saved)
            try await api.pair(clientID: saved.record.clientId, code: code)
            self.hosts = try await api.hosts(clientID: saved.record.clientId)
            self.status = "配对请求已返回。请核对并明确选择列表中的主机；不会自动选第一台。"
        }
    }

    func loadHosts() {
        run("正在读取此控制器的主机列表…") {
            let saved = try self.usableJournal(allowPairingUnknown: true)
            self.hosts = try await self.api().hosts(clientID: saved.record.clientId)
            self.status = self.hosts.isEmpty ? "服务端没有返回已配对主机。请检查桌面 Remote 设置。" : "已读取主机列表，请核对名称并选择。"
        }
    }

    func connect(hostID: String) {
        run("正在验证选定主机并连接…") {
            self.connectionExpiry?.cancel(); self.connectionExpiry = nil
            await self.relay.disconnect(); self.clearReview(); self.markDisconnected()
            var saved = try self.usableJournal(allowPairingUnknown: true)
            let api = try self.api()
            let freshHosts = try await api.hosts(clientID: saved.record.clientId)
            guard let host = freshHosts.first(where: { $0.id == hostID }), host.online else { throw RemoteConnectionError.hostUnavailable }
            self.hosts = freshHosts
            self.clearReview()
            saved.environmentID = hostID; saved.phase = .paired
            try saved.save(); self.setJournal(saved)
            let challenge = try await api.startRefresh(record: saved.record)
            let payload = try RemoteSigning.enrollmentPayload(record: saved.record, challenge: challenge.challenge,
                refresh: true, nowEpoch: Self.now)
            let proof = try self.proof(record: saved.record, challenge: challenge.challenge, payload: payload)
            let session = try await api.finishRefresh(record: saved.record, proof: proof)
            guard let account = self.account else { throw RemoteConnectionError.signInRequired }
            try self.checkForeground()
            let record = saved.record
            await self.relay.disconnect()
            self.markDisconnected()
            do {
            try await self.relay.connect(accessToken: account.accessToken, accountID: account.accountID,
                record: record, session: session, environmentID: hostID) { payload in
                    try RemoteDeviceKey.sign(record: record, payload: payload)
                }
            // A socket handshake alone never produces a Connected snapshot.
            let page = try RemoteThread.decodePage(await self.relay.listThreads())
            try self.checkForeground()
            let binding = LiveBinding(accountID: account.accountID, controllerID: record.clientId,
                environmentID: hostID, sessionID: UUID().uuidString)
            self.publish(LiveSnapshot(binding: binding, hostName: host.title, threads: page.threads, connected: true))
            self.selectedHostID = hostID
            self.status = "已读取真实主机会话（最多 20 条）。实验性连接；任务进度需手动刷新。"
            let expiry = try RemoteSigning.validateSession(record: record, session: session, nowEpoch: Self.now)
            self.expireConnection(at: min(Double(expiry), self.claims?.expiresAt.timeIntervalSince1970 ?? Double(expiry)))
            } catch { await self.relay.disconnect(); self.markDisconnected(); throw error }
        }
    }

    func refresh() { submit(.refresh) }
    func read(threadID: String) { submit(.read, threadID: threadID) }
    func send(text: String, threadID: String) { submit(.sendText, threadID: threadID, text: text) }
    func stop(threadID: String, turnID: String) { submit(.interrupt, threadID: threadID, turnID: turnID) }

    /// Called only after the UI displays the freshly read affected thread and the
    /// user explicitly acknowledges that an earlier command may have executed.
    func acknowledgeReviewedOutcome() {
        guard !busy, snapshot.fresh, var saved = journal, let pending = saved.pendingMutation,
              reviewedMutationID == pending.id, reviewedBinding == snapshot.binding,
              pending.environmentID == snapshot.binding?.environmentID,
              snapshot.threads.contains(where: { $0.id == pending.threadID }),
              let reviewedAt, Date().timeIntervalSince(reviewedAt) < 120 else {
            status = "请先打开并刷新上次操作影响的会话，核对主机结果。"; return
        }
        do {
            saved.pendingMutation = nil; try saved.save(); setJournal(saved)
            clearReview()
            status = "已记录你的核对。旧请求不会重发；之后的发送是新的指令。"
        } catch { status = Self.safeMessage(error) }
    }

    func revoke() {
        run("正在撤销此 iPhone 的控制权限…") {
            guard var saved = self.journal else { throw RemoteConnectionError.enrollmentRequired }
            let api = try self.api()
            saved.phase = .revocationUnknown; try saved.save(); self.setJournal(saved)
            await self.relay.disconnect(); self.markDisconnected()
            try await api.revoke(clientID: saved.record.clientId)
            try RemoteDeviceKey.remove(keyId: saved.record.keyId)
            try RemoteConnectionJournal.remove()
            try await self.oauth.clearStoredTokens()
            self.account = nil; self.claims = nil; self.signedIn = false
            self.journal = nil; self.enrolled = false; self.canRevoke = false
            self.needsReview = false; self.hosts = []; self.selectedHostID = nil
            self.status = "服务端撤销已确认，本机控制器密钥与登录令牌已清除。"
        }
    }

    func disconnect() {
        guard teardown == nil else { return }
        let previousOperation = operation
        previousOperation?.cancel(); operation = nil; operationID = nil
        busy = true
        connectionExpiry?.cancel(); connectionExpiry = nil
        clearReview(); markDisconnected()
        teardown = Task {
            await oauth.cancel()
            await relay.disconnect()
            await previousOperation?.value
            // A Watch callback may own a mutation task. Drain it before permitting
            // another login/connection, so old cleanup cannot cancel new work.
            while handlingID != nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            clearReview(); markDisconnected()
            busy = false; teardown = nil
            status = needsReview ? "连接已关闭。上次操作结果仍需核对，不会重发。" : "连接已关闭；不会在后台保持或自动重连。"
        }
    }
    func cancel() { disconnect() }

    func handle(command: LiveCommand) async -> LiveReply {
        guard !busy else { return reply(command, .rejected, "已有请求正在处理，未发送。") }
        busy = true; handlingID = command.id
        defer { handlingID = nil; if teardown == nil { busy = false } }
        do {
            try command.validate(); try checkForeground()
            guard snapshot.connected, command.binding == snapshot.binding else { throw RemoteConnectionError.stale }
            if command.isMutation && !snapshot.fresh { throw RemoteConnectionError.stale }
            if command.isMutation {
                guard journal?.pendingMutation == nil else { throw RemoteConnectionError.recoveryRequired }
                guard journal?.recentRequestIDs.contains(command.id) == false else {
                    return reply(command, .rejected, "此请求已处理或结果未知，不会再次执行。")
                }
            }
            switch command.kind {
            case .refresh:
                let page = try RemoteThread.decodePage(await relay.listThreads())
                try checkForeground()
                updateThreads(page.threads)
                status = "已刷新真实会话。列表未必含完整运行详情；打开会话可读取当前 turn。"
            case .read:
                let thread = try await readActual(command.threadID!)
                replace(thread)
                if let pending = journal?.pendingMutation, pending.threadID == thread.id, pending.environmentID == snapshot.binding?.environmentID {
                    reviewedMutationID = pending.id; reviewedBinding = snapshot.binding; reviewedAt = Date()
                    status = "已读取上次操作影响的会话。核对后，可明确解除未知结果锁定；不会重发原请求。"
                } else { status = "已读取真实会话。" }
            case .sendText, .interrupt:
                try await mutate(command)
            }
            return reply(command, .succeeded, status)
        } catch {
            let uncertain = journal?.pendingMutation?.id == command.id
            status = uncertain ? "指令结果未确认。不会重发；重新连接并读取原会话后核对。" : Self.safeMessage(error)
            if error is RemoteRelayError { await relay.disconnect(); markDisconnected() }
            return reply(command, uncertain ? .unknown : .rejected, status)
        }
    }

    private func mutate(_ command: LiveCommand) async throws {
        guard let threadID = command.threadID, snapshot.threads.contains(where: { $0.id == threadID }) else { throw RemoteConnectionError.stale }
        let current = try await readActual(threadID)
        replace(current)
        if command.kind == .sendText {
            guard current.state != .running, current.state != .unknown else { throw RemoteConnectionError.stale }
        } else {
            guard current.state == .running, current.currentTurnID == command.turnID else { throw RemoteConnectionError.stale }
        }
        guard snapshot.fresh, command.binding == snapshot.binding, var saved = journal else { throw RemoteConnectionError.stale }
        saved.pendingMutation = .init(id: command.id, threadID: threadID, environmentID: command.binding.environmentID, turnID: command.turnID, kind: command.kind)
        saved.recentRequestIDs.append(command.id)
        saved.recentRequestIDs = Array(saved.recentRequestIDs.suffix(100))
        try saved.save(); setJournal(saved)
        try checkForeground()
        if command.kind == .sendText {
            _ = try await relay.resumeThread(id: threadID)
            try checkForeground()
            _ = try RemoteThread.decodeStartedTurn(await relay.startTurn(threadID: threadID, text: command.text!))
            status = "主机已确认新 turn。任务尚未完成，请刷新查看。"
        } else {
            let data = try await relay.interruptTurn(threadID: threadID, turnID: command.turnID!)
            let object = try RemoteRelayCodec.object(data)
            guard object["result"] is [String: Any], object["error"] == nil else { throw RemoteConnectionError.malformedResult }
            status = "主机已确认中断请求；请刷新确认运行状态。"
        }
        // Only a correlated, schema-validated App Server response clears pending.
        saved.pendingMutation = nil; try saved.save(); setJournal(saved)
        do { replace(try await readActual(threadID)) }
        catch {
            await relay.disconnect(); markDisconnected()
            status += " 后续读取失败，连接已关闭；不会重发已确认的操作。"
        }
    }

    private func submit(_ kind: LiveCommand.Kind, threadID: String? = nil, text: String? = nil, turnID: String? = nil) {
        guard !busy, let binding = snapshot.binding else { status = "请先连接并读取真实主机会话。"; return }
        let command = LiveCommand(binding: binding, kind: kind, threadID: threadID, text: text, turnID: turnID)
        Task { _ = await handle(command: command) }
    }
    private func run(_ message: String, body: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; status = message
        let id = UUID(); operationID = id
        operation = Task {
            defer { if operationID == id { busy = false; operation = nil; operationID = nil; presenter = nil } }
            do { try checkForeground(); try await body() }
            catch { if operationID == id { status = Self.safeMessage(error) } }
        }
    }
    private func api() throws -> RemoteAPI {
        try checkForeground()
        guard let account, let claims, claims.expiresAt > Date().addingTimeInterval(60) else { throw RemoteConnectionError.signInRequired }
        return try RemoteAPI(authorization: account)
    }
    private func accept(_ tokens: CodexPlanTokens, matching existing: RemoteConnectionJournal? = nil) throws {
        let parsed = try RemoteTokenClaims.parseOrdinary(accessToken: tokens.accessToken, expectedClientID: CodexPlanOAuthConstants.clientID)
        if let existing {
            guard parsed.accountID == existing.accountID,
                  parsed.accountUserID == existing.record.accountUserId || parsed.tokenUserID == existing.record.accountUserId else {
                throw RemoteAPIError.accountMismatch
            }
        }
        claims = parsed
        account = RemoteAccountAuthorization(accessToken: tokens.accessToken, accountID: parsed.accountID,
            accountUserID: parsed.accountUserID, tokenUserID: parsed.tokenUserID)
        signedIn = true
    }
    private func usableJournal(allowPairingUnknown: Bool) throws -> RemoteConnectionJournal {
        guard let saved = journal else { throw RemoteConnectionError.enrollmentRequired }
        guard [.enrolled, .paired].contains(saved.phase) || (allowPairingUnknown && saved.phase == .pairingUnknown) else {
            throw RemoteConnectionError.recoveryRequired
        }
        guard saved.accountID == claims?.accountID, account?.accepts(saved.record.accountUserId) == true else { throw RemoteAPIError.accountMismatch }
        return saved
    }
    private func setJournal(_ value: RemoteConnectionJournal) {
        journal = value
        enrolled = [.enrolled, .paired, .pairingUnknown].contains(value.phase)
        canRevoke = true; needsReview = value.pendingMutation != nil
        reviewThreadID = value.pendingMutation?.threadID; reviewHostID = value.pendingMutation?.environmentID
    }
    private func proof(record: RemoteEnrollmentRecord, challenge: RemoteEnrollmentChallenge, payload: Data) throws -> RemoteDeviceKeyProof {
        guard challenge.challengeExpiresAt > Self.now else { throw RemoteSigningError.expiredChallenge }
        let signature = try RemoteDeviceKey.sign(record: record, payload: payload)
        return RemoteDeviceKeyProof(algorithm: record.algorithm, challengeToken: challenge.challengeToken,
            keyId: record.keyId, signatureDerBase64: signature.base64EncodedString(), signedPayloadBase64: payload.base64EncodedString())
    }
    private func readActual(_ id: String) async throws -> RemoteThread {
        let value = try RemoteThread.decodeRead(await relay.readThread(id: id), expectedThreadID: id)
        try checkForeground()
        return value
    }
    private func replace(_ thread: RemoteThread) {
        var threads = snapshot.threads
        if let index = threads.firstIndex(where: { $0.id == thread.id }) { threads[index] = thread }
        else { threads.insert(thread, at: 0); threads = Array(threads.prefix(20)) }
        updateThreads(threads)
    }
    private func updateThreads(_ threads: [RemoteThread]) {
        publish(LiveSnapshot(binding: snapshot.binding, hostName: snapshot.hostName, threads: threads, connected: snapshot.connected))
    }
    private func publish(_ value: LiveSnapshot) {
        // Bound the actual encoded bytes, including unusual Unicode/JSON escaping.
        // Reduce only display text, never IDs, run state or current-turn identity.
        var limit = 350
        var rows = Array(value.threads.prefix(20))
        while true {
            let threads = rows.map { thread in
                RemoteThread(id: thread.id, title: String(thread.title.prefix(min(100, limit))), project: String(thread.project.prefix(min(100, limit))),
                    state: thread.state, summary: String(thread.summary.prefix(limit)), currentTurnID: thread.currentTurnID, updatedAt: thread.updatedAt)
            }
            let bounded = LiveSnapshot(binding: value.binding, generatedAt: value.generatedAt, hostName: String(value.hostName.prefix(100)),
                threads: threads, connected: value.connected)
            if let encoded = try? LiveWire.encode(bounded), encoded.count < 48_000 {
                snapshot = bounded; onSnapshot?(bounded); return
            }
            if limit > 0 { limit /= 2 }
            else if !rows.isEmpty { rows.removeLast() }
            else { snapshot = .empty(); onSnapshot?(snapshot); return }
        }
    }
    private func markDisconnected() {
        publish(LiveSnapshot(binding: snapshot.binding, generatedAt: snapshot.generatedAt, hostName: snapshot.hostName,
            threads: snapshot.threads, connected: false))
    }
    private func reply(_ command: LiveCommand, _ state: LiveReply.State, _ detail: String) -> LiveReply {
        LiveReply(requestID: command.id, state: state, detail: detail, snapshot: snapshot)
    }
    private func clearReview() { reviewedMutationID = nil; reviewedBinding = nil; reviewedAt = nil }
    private func checkForeground() throws {
        try Task.checkCancellation()
        guard teardown == nil else { throw CancellationError() }
        guard UIApplication.shared.applicationState == .active else { throw RemoteConnectionError.foreground }
    }
    private func presentation() throws -> CodexOAuthSafariPresentation {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { throw CodexPlanOAuthError.browserPresenterUnavailable }
        let presenter = CodexOAuthSafariViewControllerPresenter(presentingViewController: root)
        self.presenter = presenter
        return presenter.presentation()
    }
    private func expireConnection(at timestamp: TimeInterval) {
        connectionExpiry?.cancel()
        let seconds = max(0, min(timestamp - Date().timeIntervalSince1970, 86_400))
        connectionExpiry = Task {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard await relay.isConnected() else {
                    markDisconnected(); status = "Remote 连接已断开，请明确重新连接；不会重发。"; return
                }
            }
            disconnect(); status = "连接凭证已到期，请明确重新连接；未自动刷新或重发。"
        }
    }
    private static var now: Int64 { Int64(Date().timeIntervalSince1970) }
    private static func safeMessage(_ error: Error) -> String {
        // Never surface response bodies, tokens, callbacks or arbitrary URL errors.
        if let value = error as? RemoteAPIError { return value.localizedDescription }
        if let value = error as? RemoteConnectionError { return value.localizedDescription }
        if let value = error as? RemoteTokenClaimsError { return value.localizedDescription }
        if error is CodexPlanOAuthError { return "登录或再次授权未完成。请核对登录页、取消状态和此 iPhone 的网络后重试。" }
        if error is CancellationError { return "操作已取消；已发送操作的结果仍需核对。" }
        if error is RemoteDeviceKey.Failure { return "无法使用此 iPhone 的 Secure Enclave 密钥。请使用已解锁的真机并允许系统身份验证。" }
        if error is RemoteRelayError { return "Remote 通信失败。请核对桌面版本与权限；不会自动重发。" }
        return "响应无法验证或操作未完成。不会自动重试，请核对连接状态。"
    }
}
