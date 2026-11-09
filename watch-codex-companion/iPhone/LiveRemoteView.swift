import SwiftUI

struct LiveRemoteView: View {
    @ObservedObject var controller: RemoteConnectionController
    @State private var pairingCode = ""
    @State private var confirmation: PhoneLiveConfirmation?
    var body: some View {
        NavigationStack {
            List {
                Section("真实连接 · 实验性") {
                    Text("未完成实机验证。这里不会显示演示会话，也不会导入电脑令牌或启动主机桥接。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(controller.status)
                    if controller.busy { ProgressView(); Button("取消当前操作") { controller.cancel() } }
                }
                Section("1 · 账号与控制器") {
                    Button("登录 Codex 账号") { confirmation = .signIn }.disabled(controller.busy || controller.snapshot.connected)
                    Button("恢复此 iPhone 已保存的登录") { confirmation = .restore }.disabled(controller.busy || controller.snapshot.connected)
                    if controller.signedIn {
                        Button("注册此 iPhone 控制器") { confirmation = .enroll }.disabled(controller.busy || controller.canRevoke)
                    }
                }
                if controller.enrolled {
                    Section("2 · 配对主机") {
                        Button("刷新主机列表") { controller.loadHosts() }.disabled(controller.busy)
                        SecureField("输入主机显示的配对码", text: $pairingCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("提交配对码") { confirmation = .pair(pairingCode) }
                            .disabled(controller.busy || pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(controller.hosts) { host in
                            Button { confirmation = .host(host.id, host.title) } label: {
                                VStack(alignment: .leading) { Text(host.title); Text("\(host.id) · \(host.online ? "在线" : "离线")").font(.caption) }
                            }.disabled(controller.busy || !host.online)
                        }
                    }
                }
                if controller.needsReview, let threadID = controller.reviewThreadID {
                    Section("待核对的真实操作") {
                        Text("主机环境：\(controller.reviewHostID ?? "")\n会话：\(threadID)").font(.caption)
                        Button("读取待核对会话") { controller.read(threadID: threadID) }.disabled(controller.busy || !controller.snapshot.connected)
                        Button("已核对结果，解除锁定") { controller.acknowledgeReviewedOutcome() }.disabled(controller.busy)
                    }
                }
                Section("3 · 真实会话") {
                    Button("读取主机与会话") { controller.refresh() }.disabled(controller.busy || !controller.signedIn)
                    if let binding = controller.snapshot.binding {
                        Text("主机：\(controller.snapshot.hostName)\n环境：\(binding.environmentID)").font(.caption)
                    }
                    if controller.snapshot.threads.isEmpty { Text("暂无已验证的真实会话").foregroundStyle(.secondary) }
                    ForEach(controller.snapshot.threads) { thread in
                        NavigationLink { PhoneLiveThreadView(controller: controller, threadID: thread.id) } label: {
                            VStack(alignment: .leading) { Text(thread.title); Text(thread.state.label).font(.caption) }
                        }
                    }
                }
                if controller.signedIn || controller.canRevoke {
                    Section {
                        Button("断开连接") { controller.disconnect() }.disabled(controller.busy)
                        Button("撤销控制器并清除本机凭据", role: .destructive) { confirmation = .revoke }.disabled(controller.busy || !controller.canRevoke)
                    }
                }
            }.navigationTitle("Codex Remote")
                .alert(item: $confirmation) { action in
                    Alert(title: Text(action.title), message: Text(action.message), primaryButton: .default(Text("确认")) { execute(action) }, secondaryButton: .cancel())
                }
        }
    }
    private func execute(_ action: PhoneLiveConfirmation) {
        // Wait for the confirmation alert to finish dismissing before presenting Safari.
        Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(350))
        switch action {
            case .signIn: controller.signIn()
            case .restore: controller.restore()
            case .enroll: controller.enroll()
            case .pair(let code): pairingCode = ""; controller.pair(code: code)
            case .host(let id, _): controller.connect(hostID: id)
            case .revoke: controller.revoke()
        }
        }
    }
}
private enum PhoneLiveConfirmation: Identifiable {
    case signIn, restore, enroll, pair(String), host(String, String), revoke
    var id: String { title }
    var title: String {
        switch self {
        case .signIn: return "登录并保存凭据？"
        case .restore: return "恢复已保存的登录？"
        case .enroll: return "建立持续访问权限？"
        case .pair: return "提交配对码？"
        case .host: return "连接这台主机？"
        case .revoke: return "撤销控制器？"
        }
    }
    var message: String {
        switch self {
        case .signIn: return "将打开 OpenAI 登录页面。此第三方实验使用公开 Codex 应用标识，未经服务方验证。登录令牌会存入此 iPhone 的设备专属钥匙串，仅发送到 OpenAI 的登录及 Remote 服务，不发送给 Watch。注册设备密钥需另行确认。"
        case .restore: return "将使用此 iPhone 已保存的凭据恢复账号，并向官方服务验证状态。"
        case .enroll: return "将向 Codex Remote 注册此 iPhone 控制器并创建持续访问凭据。之后可操作已配对主机，直到撤销。"
        case .pair: return "将把刚输入的主机配对码提交给当前登录账号的 Codex Remote 服务。请确认这是你要授权的主机。"
        case .host(let id, let name): return "主机：\(name)\n环境：\(id)\n将读取该主机的真实会话。"
        case .revoke: return "将尝试撤销服务端控制器，并清除本机凭据。Watch 将无法继续控制；具体结果请查看回执。"
        }
    }
}

private struct PhoneLiveThreadView: View {
    @ObservedObject var controller: RemoteConnectionController
    let threadID: String
    @State private var text = ""
    @State private var pending: LiveCommand?
    @State private var showConfirmation = false
    @State private var localStatus = ""
    private var thread: RemoteThread? { controller.snapshot.threads.first { $0.id == threadID } }
    var body: some View {
        Form {
            Text(thread?.title ?? threadID)
            Text("主机：\(controller.snapshot.hostName)\n会话：\(threadID)").font(.caption)
            Text(thread?.summary ?? "请读取详情")
            Text(controller.status).font(.caption)
            if !localStatus.isEmpty { Text(localStatus).foregroundStyle(.orange) }
            Button("读取最新详情") { controller.read(threadID: threadID) }.disabled(controller.busy)
            if controller.needsReview {
                Text("操作结果未确认，请先读取对应会话并核对。")
                Button("已核对结果，解除锁定") { controller.acknowledgeReviewedOutcome() }.disabled(controller.busy)
            }
            TextField("发送内容（最多 2000 字）", text: $text, axis: .vertical)
            Button("检查并发送") { prepare(.sendText) }.disabled(controller.busy || controller.needsReview || !controller.snapshot.fresh || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
            Button("停止当前轮次", role: .destructive) { prepare(.interrupt) }
                .disabled(controller.busy || controller.needsReview || !controller.snapshot.fresh || thread?.currentTurnID == nil)
        }.navigationTitle("真实会话")
            .alert("确认真实操作", isPresented: $showConfirmation) {
                Button("取消", role: .cancel) { pending = nil }
                Button("确认执行", role: .destructive) { execute() }
            } message: {
                Text("主机：\(controller.snapshot.hostName)\n环境：\(pending?.binding.environmentID ?? "")\n会话：\(pending?.threadID ?? "")\n\(pending?.kind == .interrupt ? "停止轮次：\(pending?.turnID ?? "")" : "发送：\(pending?.text ?? "")")")
            }
    }
    private func prepare(_ kind: LiveCommand.Kind) {
        guard let binding = controller.snapshot.binding else { return }
        pending = LiveCommand(binding: binding, kind: kind, threadID: threadID, text: kind == .sendText ? text : nil, turnID: kind == .interrupt ? thread?.currentTurnID : nil)
        showConfirmation = true
    }
    private func execute() {
        guard let command = pending else { return }; pending = nil
        guard command.binding == controller.snapshot.binding, controller.snapshot.fresh,
              (try? command.validate()) != nil else { localStatus = "连接已变化或确认已过期，请重新核对。"; return }
        Task {
            let reply = await controller.handle(command: command)
            localStatus = reply.detail
            if reply.state == .succeeded && command.kind == .sendText { text = "" }
        }
    }
}
