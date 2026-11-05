import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "applewatch.radiowaves.left.and.right")
                            .font(.title).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("抬腕，接着做。")
                                .font(.title2.weight(.semibold))
                            Text("查看已有会话，留一句指令，核对结果。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                    Label("演示模式 · Remote 尚未连接", systemImage: "network.slash")
                        .font(.subheadline.weight(.medium))
                    LabeledContent("设备链路") { Text(store.reachable ? "可达" : "暂不可达").foregroundStyle(.secondary) }
                    Text(store.linkStatus).font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text("手机与手表可达，不代表已登录或连接 Codex Remote。所有会话和进度均为示例。")
                }
                Section {
                    ForEach(store.snapshot.threads) { thread in
                        NavigationLink { PhoneThreadView(threadID: thread.id) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(thread.project).font(.caption).foregroundStyle(.secondary)
                                    Spacer(minLength: 10)
                                    Label(thread.state.label, systemImage: thread.state.symbol)
                                        .font(.caption).foregroundStyle(thread.state == .running ? Color.accentColor : .secondary)
                                }
                                Text(thread.title).font(.headline)
                                Text(thread.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 6)
                        }
                    }
                } header: {
                    HStack { Text("示例会话"); Spacer(); Text("\(store.snapshot.threads.count) 个已有 thread") }
                } footer: {
                    Text("快照生成于 \(store.snapshot.generatedAt.formatted(date: .omitted, time: .standard))。不会自动新建会话。")
                }
                Section("最近回执") {
                    Text(store.receipt).font(.subheadline).textSelection(.enabled)
                }
                Section {
                    NavigationLink { ConnectionDetailsView() } label: { Label("连接与实现边界", systemImage: "point.3.connected.trianglepath.dotted") }
                }
            }
            .navigationTitle("Codex Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refresh() } label: { Label("刷新演示", systemImage: "arrow.clockwise") }
                        .disabled(store.busy)
                }
            }
            .refreshable { store.refresh() }
        }
    }
}

struct PhoneThreadView: View {
    @EnvironmentObject private var store: CompanionStore
    let threadID: String
    @State private var draft = ""
    @State private var confirmStop = false
    @State private var stopTarget: ThreadSummary?
    var body: some View {
        Group {
            if let thread = store.thread(threadID) {
                List {
                    Section {
                        Label(thread.state.label, systemImage: thread.state.symbol)
                            .foregroundStyle(thread.state == .running ? Color.accentColor : .secondary)
                        Text(thread.summary).font(.body).textSelection(.enabled)
                    } header: { Text(thread.project) } footer: { Text("示例内容 · Remote 未连接") }
                    Section("在已有会话里继续") {
                        TextField("输入演示指令", text: $draft, axis: .vertical)
                            .lineLimit(3...8)
                            .accessibilityHint("最多 2000 字，仅用于本地演示")
                        HStack {
                            Text("\(draft.count) / 2000").font(.caption).foregroundStyle(draft.count > 2000 ? Color.red : .secondary)
                            Spacer()
                            Button("模拟发送", systemImage: "arrow.up.circle.fill") {
                                store.send(text: draft, threadID: threadID)
                            }.disabled(!store.canMutate || thread.state == .running || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                        }
                    } footer: {
                        Text(thread.state == .running ? "先模拟停止当前 turn，再体验发送新指令。" : "输入保留在当前页面，不发送到任何 Remote 主机。")
                    }
                    if thread.currentTurnID != nil {
                        Section {
                            Button("模拟停止此 turn", role: .destructive) { stopTarget = thread; confirmStop = true }
                                .disabled(!store.canMutate)
                        }
                    }
                    Section("回执") { Text(store.receipt).font(.subheadline) }
                    Section("已有标识") {
                        Text(thread.id).font(.caption.monospaced()).textSelection(.enabled)
                        if let turn = thread.currentTurnID { Text(turn).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("只停止当前示例 turn？", isPresented: $confirmStop, titleVisibility: .visible) {
                    Button("模拟停止", role: .destructive) {
                        if let target = stopTarget { store.stop(target) }
                        stopTarget = nil
                    }
                    Button("取消", role: .cancel) { stopTarget = nil }
                } message: { Text("不会影响真实 Codex Remote 任务。") }
            } else {
                ContentUnavailableView("会话不在快照中", systemImage: "text.bubble", description: Text("返回并刷新。不会创建替代会话。"))
            }
        }
    }
}

struct ConnectionDetailsView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        List {
            Section("当前状态") {
                Label("Codex Remote 尚未连接", systemImage: "network.slash")
                Label(store.reachable ? "设备链路可达" : "设备链路暂不可达", systemImage: "iphone.and.arrow.forward")
                Text("iOS 原生 Remote 授权入口尚未确认，因此这里没有登录按钮，也不会借用桌面 client 或读取桌面 token。")
            }
            Section("可以体验") {
                Label("三个已有示例会话", systemImage: "text.bubble")
                Label("本机发送与明确 turn 的停止演示", systemImage: "hand.tap")
                Label("通过 WatchConnectivity 交换演示快照", systemImage: "applewatch")
            }
            Section("尚待验证") {
                Text("获准的 iOS 授权入口 → 明确确认密钥与控制器授权 → 指定已有主机的只读联调 → 指定 thread 的真实指令。")
                Text("本工程不登录、不 enroll、不配对、不创建持久密钥、不打开 Remote WebSocket。")
            }
        }.navigationTitle("连接与边界").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { PhoneRootView().environmentObject(CompanionStore()) }
