import SwiftUI

@MainActor
final class LiveCompanionStore: ObservableObject {
    @Published private(set) var snapshot = LiveSnapshot.empty()
    @Published private(set) var reachable = false
    @Published private(set) var busy = false
    @Published private(set) var receipt = "真实连接尚未建立。请先在 iPhone 登录、配对并选择主机。"
    @Published private(set) var uncertain = UserDefaults.standard.bool(forKey: "live.uncertainMutation")
    @Published private(set) var canReview = false
    private let connectivity: CompanionConnectivity
    private var pendingID: UUID?
    private var uncertainBinding = UserDefaults.standard.data(forKey: "live.uncertainBinding").flatMap { try? JSONDecoder().decode(LiveBinding.self, from: $0) }
    private var uncertainThreadID = UserDefaults.standard.string(forKey: "live.uncertainThreadID")
    #if os(iOS)
    let controller = RemoteConnectionController()
    #endif

    init(connectivity: CompanionConnectivity) {
        self.connectivity = connectivity
        #if os(watchOS)
        connectivity.onLiveSnapshot = { [weak self] snapshot in
            guard let self else { return }
            // Context updates never resolve an uncertain mutation.
            if snapshot.generatedAt >= self.snapshot.generatedAt || self.snapshot.binding == nil {
                if snapshot.binding != self.snapshot.binding { self.canReview = false }
                self.snapshot = snapshot
            }
        }
        #endif
        #if os(iOS)
        controller.onSnapshot = { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.connectivity.publishLive(snapshot)
        }
        connectivity.onLiveCommand = { [weak self] command, reply in
            guard let self else { return }
            Task { reply(await self.controller.handle(command: command)) }
        }
        #endif
    }
    func updateReachable(_ value: Bool) { reachable = value }
    func publish() { connectivity.publishLive(snapshot) }
    var canMutate: Bool { !busy && !uncertain && reachable && snapshot.fresh }
    func reviewed() {
        guard canReview, snapshot.fresh, !busy else { return }
        setUncertain(false); canReview = false
        receipt = "已核对最新状态。再次发送仍需要确认。"
    }
    private func setUncertain(_ value: Bool) {
        uncertain = value
        UserDefaults.standard.set(value, forKey: "live.uncertainMutation")
    }
    func perform(_ command: LiveCommand) {
        guard !busy, reachable else { receipt = "iPhone 不可达或请求仍在处理中；未发送。"; return }
        guard command.binding == snapshot.binding, (try? command.validate()) != nil else {
            receipt = "账号、主机或会话已变化，请刷新后重新确认。"; return
        }
        guard !command.isMutation || canMutate else { receipt = "先刷新并核对结果，再执行操作。"; return }
        busy = true; pendingID = command.id; canReview = false
        if command.isMutation {
            uncertainBinding = command.binding
            UserDefaults.standard.set(try? JSONEncoder().encode(command.binding), forKey: "live.uncertainBinding")
            uncertainThreadID = command.threadID
            UserDefaults.standard.set(command.threadID, forKey: "live.uncertainThreadID")
            setUncertain(true)
        }
        receipt = "等待 iPhone 回执；不会排队或自动重发。"
        connectivity.sendLive(command) { [weak self] result in
            guard let self, self.pendingID == command.id else { return }
            self.pendingID = nil; self.busy = false
            switch result {
            case .success(let reply):
                self.receipt = reply.detail
                if reply.snapshot.generatedAt >= self.snapshot.generatedAt {
                    self.snapshot = reply.snapshot
                }
                if command.isMutation, reply.state != .unknown { self.setUncertain(false) }
                if command.kind == .read, command.threadID == self.uncertainThreadID, self.matchesUncertainHost(command.binding), reply.state == .succeeded,
                   reply.snapshot.binding == command.binding, self.snapshot.binding == command.binding, reply.snapshot.fresh { self.canReview = true }
            case .failure(let error):
                self.receipt = "结果未确认：\(error.localizedDescription)。请刷新核对，不要重复发送。"
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.pendingID == command.id else { return }
            self.pendingID = nil; self.busy = false
            self.receipt = "等待回执超时，结果未知。不会重发；请刷新并核对。"
        }
    }
    private func matchesUncertainHost(_ binding: LiveBinding) -> Bool {
        guard let previous = uncertainBinding else { return false }
        // Reading after reconnect uses a new session; mutations still require full equality.
        return binding.accountID == previous.accountID && binding.controllerID == previous.controllerID
            && binding.environmentID == previous.environmentID
    }
    func refresh() {
        guard let binding = snapshot.binding else { receipt = "请先在 iPhone 建立真实连接。"; return }
        perform(LiveCommand(binding: binding, kind: .refresh))
    }
    func read(_ threadID: String) {
        guard let binding = snapshot.binding else { return }
        perform(LiveCommand(binding: binding, kind: .read, threadID: threadID))
    }
}
