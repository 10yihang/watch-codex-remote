import SwiftUI

struct LiveWatchView: View {
    @ObservedObject var store: LiveCompanionStore
    var body: some View {
        NavigationStack {
            List {
                Text("真实连接 · 实验性／未验证").font(.caption).foregroundStyle(.orange)
                Text(store.snapshot.hostName).font(.headline)
                Text(store.reachable ? "iPhone 可达" : "iPhone 不可达").font(.caption)
                Text(store.snapshot.connected ? "快照：\(store.snapshot.generatedAt.formatted(date: .omitted, time: .standard))" : "尚未连接真实主机").font(.caption)
                Text(store.receipt).font(.caption)
                Button("刷新真实会话") { store.refresh() }.disabled(store.busy || !store.reachable)
                if store.uncertain {
                    Text("上次操作结果未确认。先在 iPhone 核对并解除锁定，再读取此会话详情并核对。")
                        .font(.caption).foregroundStyle(.orange)
                }
                if store.snapshot.threads.isEmpty { Text("请在 iPhone 登录并连接主机。无演示数据。") }
                ForEach(store.snapshot.threads) { thread in
                    NavigationLink { LiveWatchThreadView(store: store, threadID: thread.id) } label: {
                        VStack(alignment: .leading) { Text(thread.title); Text(thread.state.label).font(.caption) }
                    }
                }
            }.navigationTitle("Remote")
        }
    }
}
private struct LiveWatchThreadView: View {
    @ObservedObject var store: LiveCompanionStore
    let threadID: String
    @State private var text = ""
    @State private var pending: LiveCommand?
    @State private var showConfirmation = false
    private var thread: RemoteThread? { store.snapshot.threads.first { $0.id == threadID } }
    var body: some View {
        List {
            Text(thread?.title ?? threadID)
            Text("主机：\(store.snapshot.hostName)\n会话：\(threadID)").font(.caption)
            Text(thread?.summary ?? "读取详情后操作")
            Text(store.receipt).font(.caption)
            Button("读取最新详情") { store.read(threadID) }.disabled(store.busy || !store.reachable)
            if store.uncertain && store.canReview {
                Button("已核对结果，解除锁定") { store.reviewed() }
            }
            TextField("发送内容", text: $text)
            Text("\(text.count)/2000").font(.caption)
            Button("检查并发送") { prepare(.sendText) }
                .disabled(!store.canMutate || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
            Button("停止当前轮次", role: .destructive) { prepare(.interrupt) }
                .disabled(!store.canMutate || thread?.currentTurnID == nil)
        }.navigationTitle("真实会话")
            .alert("确认真实操作", isPresented: $showConfirmation) {
                Button("取消", role: .cancel) { pending = nil }
                Button("确认执行", role: .destructive) {
                    if let pending { store.perform(pending) }
                    pending = nil
                }
            } message: {
                Text("主机：\(store.snapshot.hostName)\n环境：\(pending?.binding.environmentID ?? "")\n会话：\(pending?.threadID ?? "")\n\(pending?.kind == .interrupt ? "停止轮次：\(pending?.turnID ?? "")" : "发送：\(pending?.text ?? "")")")
            }
    }
    private func prepare(_ kind: LiveCommand.Kind) {
        guard let binding = store.snapshot.binding else { return }
        pending = LiveCommand(binding: binding, kind: kind, threadID: threadID,
                              text: kind == .sendText ? text : nil, turnID: kind == .interrupt ? thread?.currentTurnID : nil)
        showConfirmation = true
    }
}
