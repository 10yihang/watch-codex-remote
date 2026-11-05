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
                    .foregroundStyle(Color.primary.opacity(0.65))

                    if store.snapshot.threads.isEmpty {
                        ContentUnavailableView("还没有示例会话", systemImage: "text.bubble",
                                               description: Text("刷新以重新获取演示快照。"))
                    }
                    ForEach(activeThreads) { thread in
                        NavigationLink(value: thread.id) {
                            PhoneActiveSession(thread: thread)
                        }.buttonStyle(.plain)
                    }
                    if !otherThreads.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近会话").font(.title3.weight(.semibold))
                                .padding(.bottom, 8)
                            ForEach(otherThreads) { thread in
                                NavigationLink(value: thread.id) {
                                    HStack(spacing: 14) {
                                        Image(systemName: thread.state.symbol)
                                            .font(.title3).foregroundStyle(Color.primary.opacity(0.65))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(thread.title).font(.headline).foregroundStyle(.primary)
                                            Text("\(thread.project) · \(thread.state.label)")
                                                .font(.subheadline).foregroundStyle(Color.primary.opacity(0.65))
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
                                        .font(.caption).foregroundStyle(Color.primary.opacity(0.65))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .background(.thinMaterial,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                            }
                        }.buttonStyle(.plain)
                        Text(store.receipt)
                            .font(.caption).foregroundStyle(Color.primary.opacity(0.65)).textSelection(.enabled)
                        Text("快照更新于 \(store.snapshot.generatedAt.formatted(date: .omitted, time: .shortened)) · 所有会话均为示例")
                            .font(.caption2).foregroundStyle(Color.primary.opacity(0.65))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background { PhoneGlassBackdrop() }
            .navigationTitle("Codex")
            .navigationDestination(for: String.self) { threadID in
                PhoneThreadView(threadID: threadID)
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let thread: ThreadSummary
    var body: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        VStack(alignment: .leading, spacing: 16) {
            headerLayout {
                Label(thread.state.label, systemImage: thread.state.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(thread.project).font(.caption).foregroundStyle(Color.primary.opacity(0.65))
            }
            Text(thread.title).font(.title2.weight(.bold)).foregroundStyle(.primary)
            Text(thread.summary).font(.subheadline).foregroundStyle(Color.primary.opacity(0.65))
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
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// Native materials need a varied backdrop to reveal their translucency.
private struct PhoneGlassBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                Ellipse()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.height * 0.6)
                    .blur(radius: 55)
                    .offset(x: -geometry.size.width * 0.35, y: -geometry.size.height * 0.25)
                Ellipse()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                    .blur(radius: 65)
                    .offset(x: geometry.size.width * 0.35, y: geometry.size.height * 0.2)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
    @State private var diagnostic = "尚未运行本机协议检查。"
    var body: some View {
        List {
            Section("当前状态") {
                Label("Codex Remote 尚未连接", systemImage: "network.slash")
                Label(store.reachable ? "设备链路可达" : "设备链路暂不可达", systemImage: "iphone.and.arrow.forward")
                Text(store.linkStatus).font(.caption).foregroundStyle(Color.primary.opacity(0.65))
                Text("仍缺少获准的 iOS Remote 登录配置。公开的第三方 ChatGPT 登录不等于 Remote 控制权限，因此真实连接保持关闭。")
            }
            Section("可以体验") {
                Label("三个已有示例会话", systemImage: "text.bubble")
                Label("本机发送与明确 turn 的停止演示", systemImage: "hand.tap")
                Label("通过 WatchConnectivity 交换演示快照", systemImage: "applewatch")
            }
            Section("已写入原生连接层 · 尚未联调") {
                Label("设备挑战签名与令牌绑定校验", systemImage: "signature")
                Label("Secure Enclave 密钥保存与签名", systemImage: "lock.shield")
                Label("注册、会话续期、配对与撤销请求", systemImage: "link")
                Label("Relay 收发与已有会话只读访问", systemImage: "network")
                Text("这些组件尚未用于你的账号或主机。设备密钥不会自动创建，真实会话也不会混入演示列表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本机协议检查") {
                Button("检查签名与协议编码", systemImage: "checkmark.shield") {
                    do { diagnostic = try RemoteDiagnostics.run() }
                    catch { diagnostic = "本机协议检查失败。请保留此版本并查看构建测试；没有发起真实连接。" }
                }
                Text(diagnostic).font(.caption).accessibilityIdentifier("remote-diagnostic-result")
            }
            Section("下一步") {
                Text("获准的 Remote OAuth 客户端与 iOS 回调 → 你确认设备授权 → 指定主机的只读联调 → 指定已有会话的真实指令。")
                Text("登录、配对和真实指令尚不可用。不会粘贴桌面 token、冒用桌面客户端，或在主机加装桥接服务。")
            }
        }.navigationTitle("连接与边界").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { PhoneRootView().environmentObject(CompanionStore()) }
