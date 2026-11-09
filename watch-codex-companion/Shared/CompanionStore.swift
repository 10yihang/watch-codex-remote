import SwiftUI

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    @Published private(set) var reachable = false
    @Published private(set) var linkStatus = "设备链路启动中"
    @Published private(set) var receipt = "所有内容均为演示。Remote 尚未连接。"
    @Published private(set) var busy = false
    @Published var usePhone = false { didSet { switchSource() } }
    private var engine: DemoEngine
    private let connectivity: CompanionConnectivity
    let live: LiveCompanionStore
    private var phoneSnapshot: Snapshot?
    private var pendingID: UUID?
    private var uncertainMutation = false

    init() {
        let engine = DemoEngine()
        self.engine = engine
        snapshot = engine.snapshot
        let connectivity = CompanionConnectivity()
        self.connectivity = connectivity
        live = LiveCompanionStore(connectivity: connectivity)
        connectivity.onStatus = { [weak self] reachable, status in
            guard let self else { return }
            self.reachable = reachable; self.linkStatus = status
            self.live.updateReachable(reachable)
        }
        #if os(iOS)
        connectivity.onActivated = { [weak self] in
            guard let self else { return }; self.connectivity.publish(self.snapshot); self.live.publish()
        }
        #endif
        connectivity.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            #if os(watchOS)
            if let previous = self.phoneSnapshot, snapshot.generatedAt < previous.generatedAt { return }
            self.phoneSnapshot = snapshot
            if self.usePhone { self.snapshot = snapshot }
            #endif
        }
        #if os(iOS)
        connectivity.onCommand = { [weak self] command in
            guard let self else { return Reply(requestID: command.id, state: .rejected, detail: "iPhone 尚未就绪", snapshot: .empty()) }
            let reply = self.engine.handle(command)
            self.snapshot = self.engine.snapshot
            self.receipt = "已收到 Watch 请求 · \(reply.detail)"
            self.connectivity.publish(self.snapshot)
            return reply
        }
        #endif
        connectivity.activate()
    }
    var sourceLabel: String { usePhone ? "iPhone 演示" : "本机演示" }
    var canMutate: Bool { !busy && (!usePhone || (!uncertainMutation && reachable)) }
    func thread(_ id: String) -> ThreadSummary? { snapshot.threads.first { $0.id == id } }
    func refresh() { perform(Command(kind: .refresh)) }
    func send(text: String, threadID: String) { perform(Command(kind: .sendText, threadID: threadID, text: text)) }
    func stop(_ thread: ThreadSummary) {
        guard let turnID = thread.currentTurnID else { return }
        perform(Command(kind: .interrupt, threadID: thread.id, turnID: turnID))
    }
    private func switchSource() {
        // Do not redirect an in-flight command to another transport.
        guard !busy else { return }
        snapshot = usePhone ? (phoneSnapshot ?? .empty()) : engine.snapshot
        receipt = usePhone ? "从 iPhone 获取演示快照。Remote 仍未连接。" : "本机演示，不发送到 iPhone 或 Remote。"
    }
    private func perform(_ command: Command) {
        guard !busy else { return }
        if command.kind != .refresh && !canMutate { return }
        guard usePhone else {
            let reply = engine.handle(command)
            snapshot = engine.snapshot; receipt = reply.detail
            #if os(iOS)
            connectivity.publish(snapshot)
            #endif
            return
        }
        guard reachable else { receipt = "iPhone 当前不可达；请求未发送。打开手机 App 后刷新。"; return }
        busy = true; pendingID = command.id
        receipt = "正在发送到 iPhone；尚未收到回执。Remote 未连接。"
        connectivity.send(command) { [weak self] result in
            guard let self, self.pendingID == command.id else { return }
            self.pendingID = nil; self.busy = false
            switch result {
            case .success(let reply):
                self.receipt = "已收到 iPhone 回执 · \(reply.detail)"
                if reply.snapshot.generatedAt >= (self.phoneSnapshot?.generatedAt ?? .distantPast) {
                    self.phoneSnapshot = reply.snapshot; self.snapshot = reply.snapshot
                }
                if command.kind == .refresh && reply.state == .demoApplied { self.uncertainMutation = false }
            case .failure(let error):
                if command.kind != .refresh { self.uncertainMutation = true }
                self.receipt = "未确认结果：\(error.localizedDescription)。不会自动重发；先刷新核对。"
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.pendingID == command.id else { return }
            self.pendingID = nil; self.busy = false
            if command.kind != .refresh { self.uncertainMutation = true }
            self.receipt = "等待 iPhone 回执超时，结果未知。不会自动重发；先刷新核对。"
        }
    }
}
