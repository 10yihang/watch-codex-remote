import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var store: CompanionStore
    private var activeThreads: [ThreadSummary] { store.snapshot.threads.filter { $0.state == .running } }
    private var otherThreads: [ThreadSummary] { store.snapshot.threads.filter { $0.state != .running } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 8) {
                        Label("演示模式", systemImage: "circle.dashed")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Remote 未连接").font(.subheadline)
                    }
                    .foregroundStyle(.secondary)

                    if store.snapshot.threads.isEmpty {
                        ContentUnavailableView("还没有示例会话", systemImage: "text.bubble",
                                               description: Text("刷新以重新获取演示快照。"))
                    }
                    ForEach(activeThreads) { thread in
                        NavigationLink { PhoneThreadView(threadID: thread.id) } label: {
                            PhoneActiveSession(thread: thread)
                        }.buttonStyle(.plain)
                    }
                    if !otherThreads.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近会话").font(.title3.weight(.semibold))
                                .padding(.bottom, 8)
                            ForEach(otherThreads) { thread in
                                NavigationLink { PhoneThreadView(threadID: thread.id) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: thread.state.symbol)
                                            .font(.title3).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(thread.title).font(.headline).foregroundStyle(.primary)
                                            Text("\(thread.project) · \(thread.state.label)")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 15)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if thread.id != otherThreads.last?.id { Divider().padding(.leading, 36) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        NavigationLink { ConnectionDetailsView() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "applewatch").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Apple Watch").font(.subheadline.weight(.semibold))
                                    Text(store.reachable ? "设备链路可达" : "设备暂不可达")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(.plain)
                        Text(store.receipt)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("快照更新于 \(store.snapshot.generatedAt.formatted(date: .omitted, time: .shortened)) · 所有会话均为示例")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Codex")
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

private struct PhoneActiveSession: View {
    let thread: ThreadSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(thread.state.label, systemImage: thread.state.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                Spacer(minLength: 8)
                Text(thread.project).font(.caption).foregroundStyle(.secondary)
            }
            Text(thread.title).font(.title2.weight(.bold)).foregroundStyle(.primary)
            Text(thread.summary).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("查看会话").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
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
                    Section {
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
                    } header: {
                        Text("在已有会话里继续")
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
                Text(store.linkStatus).font(.caption).foregroundStyle(.secondary)
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
