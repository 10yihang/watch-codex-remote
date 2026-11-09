import SwiftUI

struct LiveRemoteView: View {
    @ObservedObject var controller: RemoteConnectionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pairingCode = ""
    @State private var confirmation: PhoneLiveConfirmation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    connectionOverview
                    if controller.needsReview, let threadID = controller.reviewThreadID {
                        reviewPanel(threadID: threadID)
                    }
                    if controller.snapshot.connected || !controller.snapshot.threads.isEmpty {
                        sessions
                    }
                    if !controller.snapshot.connected {
                        accountSetup
                        if controller.enrolled { hostSetup }
                        if controller.snapshot.threads.isEmpty { emptySessions }
                    } else {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 24) {
                                accountSetup
                                if controller.enrolled { hostSetup }
                            }.padding(.top, 20)
                        } label: {
                            Text("连接设置").frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .font(.headline)
                        .remotePhoneSurface()
                    }
                    connectionNotes
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background { RemotePhoneBackdrop() }
            .navigationTitle("Codex Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { controller.refresh() } label: {
                        Label("刷新会话", systemImage: "arrow.clockwise")
                    }.disabled(controller.busy || !controller.snapshot.connected)
                }
            }
            .alert(item: $confirmation) { action in
                Alert(title: Text(action.title), message: Text(action.message), primaryButton: .default(Text("确认")) { execute(action) }, secondaryButton: .cancel())
            }
        }
    }

    private var connectionOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: controller.snapshot.connected ? "laptopcomputer" : "link")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.09), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.snapshot.connected ? controller.snapshot.hostName : "连接你的 Codex")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(controller.snapshot.connected ? "查看已有会话，在手腕上继续。" : "在 iPhone 完成设置，再从 Watch 查看与控制已有会话。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                connectionStep("账号", complete: controller.signedIn)
                connectionStep("控制器", complete: controller.enrolled)
                connectionStep("主机", complete: controller.snapshot.connected)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if controller.busy {
                    HStack(alignment: .top, spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(controller.status).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("取消当前操作", role: .cancel) { controller.cancel() }
                        .buttonStyle(.bordered).controlSize(.large)
                } else {
                    Text(controller.status)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Label("实验性 · 未完成实机验证", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .remotePhoneSurface()
    }

    private func connectionStep(_ title: String, complete: Bool) -> some View {
        Label(title, systemImage: complete ? "checkmark.circle.fill" : "circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(complete ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(title)，\(complete ? "已完成" : "未完成")")
    }

    private var accountSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账号与控制器").font(.title3.weight(.semibold))
            if !controller.signedIn {
                Text("使用 Codex 账号登录。凭据只保存在此 iPhone。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button { confirmation = .signIn } label: {
                Label("登录 Codex 账号", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(controller.busy || controller.snapshot.connected)
            Button { confirmation = .restore } label: {
                Label("恢复此 iPhone 已保存的登录", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(controller.busy || controller.snapshot.connected)
            if controller.signedIn {
                Button { confirmation = .enroll } label: {
                    Label("注册此 iPhone 控制器", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(controller.busy || controller.canRevoke)
            }
        }
    }

    private var hostSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("配对主机").font(.title3.weight(.semibold))
                Spacer(minLength: 12)
                Button { controller.loadHosts() } label: {
                    Label("刷新主机列表", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.disabled(controller.busy)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("输入主机显示的配对码").font(.subheadline.weight(.medium))
                SecureField("配对码", text: $pairingCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("输入主机显示的配对码")
                Button { confirmation = .pair(pairingCode) } label: {
                    Label("提交配对码", systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(controller.busy || pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !controller.hosts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(controller.hosts) { host in
                        Button { confirmation = .host(host.id, host.title) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "laptopcomputer")
                                    .font(.title3).foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(host.title).font(.headline).foregroundStyle(.primary)
                                    Label(host.online ? "在线" : "离线", systemImage: host.online ? "circle.fill" : "circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(host.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(controller.busy || !host.online)
                        if host.id != controller.hosts.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("真实会话").font(.title3.weight(.semibold))
                Spacer()
                Text("\(controller.snapshot.threads.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if controller.snapshot.threads.isEmpty { emptySessions }
            ForEach(controller.snapshot.threads) { thread in
                NavigationLink {
                    PhoneLiveThreadView(controller: controller, threadID: thread.id)
                } label: {
                    RemotePhoneThreadRow(thread: thread)
                }.buttonStyle(.plain)
            }
        }
    }

    private var emptySessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂无已验证的真实会话", systemImage: "text.bubble")
                .font(.headline)
            Text(controller.snapshot.connected ? "刷新会话，查看这台主机已有的工作。" : "连接主机后，会话会显示在这里。这里不会混入演示数据。")
                .font(.subheadline).foregroundStyle(.secondary)
            if controller.snapshot.connected {
                Button("刷新会话") { controller.refresh() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(controller.busy || !controller.snapshot.connected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewPanel(threadID: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("待核对的真实操作", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(Color.orange)
            Text("先读取对应会话，核对上次操作的结果。")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("主机环境：\(controller.reviewHostID ?? "")\n会话：\(threadID)")
                .font(.caption.monospaced()).textSelection(.enabled)
            Button("读取待核对会话") { controller.read(threadID: threadID) }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(controller.busy || !controller.snapshot.connected)
            Button("已核对结果，解除锁定") { controller.acknowledgeReviewedOutcome() }
                .buttonStyle(.bordered).controlSize(.large).disabled(controller.busy)
        }.remotePhoneSurface()
    }

    private var connectionNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let binding = controller.snapshot.binding {
                DisclosureGroup {
                    Text("主机：\(controller.snapshot.hostName)\n环境：\(binding.environmentID)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    Text("连接信息").frame(minHeight: 44).contentShape(Rectangle())
                }.font(.subheadline)
            }
            Text("iPhone 需保持前台解锁。不导入电脑令牌，不启动额外主机桥接。")
                .font(.caption).foregroundStyle(.secondary)
            if controller.signedIn || controller.canRevoke {
                Divider()
                Button("断开连接") { controller.disconnect() }
                    .buttonStyle(.bordered).controlSize(.large).disabled(controller.busy)
                Button("撤销控制器并清除本机凭据", role: .destructive) { confirmation = .revoke }
                    .buttonStyle(.bordered).controlSize(.large).disabled(controller.busy || !controller.canRevoke)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    if let thread {
                        Label(thread.state.label, systemImage: thread.state.phoneSymbol)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(thread.state.phoneColor)
                    }
                    Text(thread?.title ?? threadID).font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(thread?.summary ?? "请读取详情")
                        .font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.remotePhoneSurface()

                VStack(alignment: .leading, spacing: 14) {
                    Text("最新状态").font(.headline)
                    Text(controller.status).font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !localStatus.isEmpty {
                        Label(localStatus, systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(Color.orange)
                    }
                    Button("读取最新详情", systemImage: "arrow.clockwise") { controller.read(threadID: threadID) }
                        .buttonStyle(.bordered).controlSize(.large).disabled(controller.busy)
                    if controller.needsReview {
                        Text("操作结果未确认，请先读取对应会话并核对。")
                            .font(.subheadline).foregroundStyle(Color.orange)
                        Button("已核对结果，解除锁定") { controller.acknowledgeReviewedOutcome() }
                            .buttonStyle(.bordered).controlSize(.large).disabled(controller.busy)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("继续这个会话").font(.title3.weight(.semibold))
                    TextField("发送内容（最多 2000 字）", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityHint("输入保留在此页面，检查后还需要确认才能发送")
                    Divider()
                    Text("\(text.count) / 2000")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(text.count > 2000 ? Color.red : Color.secondary)
                    Button { prepare(.sendText) } label: {
                        Label("检查并发送", systemImage: "arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(controller.busy || controller.needsReview || !controller.snapshot.fresh || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                }.remotePhoneSurface()

                Button("停止当前轮次", systemImage: "stop.circle", role: .destructive) { prepare(.interrupt) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(controller.busy || controller.needsReview || !controller.snapshot.fresh || thread?.currentTurnID == nil)

                DisclosureGroup {
                    Text("主机：\(controller.snapshot.hostName)\n会话：\(threadID)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                } label: {
                    Text("会话标识").frame(minHeight: 44).contentShape(Rectangle())
                }.font(.subheadline)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
        .background { RemotePhoneBackdrop() }
        .navigationTitle("真实会话")
        .navigationBarTitleDisplayMode(.inline)
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

private struct RemotePhoneThreadRow: View {
    let thread: RemoteThread
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(thread.state.label, systemImage: thread.state.phoneSymbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(thread.state.phoneColor)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(thread.title).font(.headline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !thread.summary.isEmpty {
                Text(thread.summary).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if !thread.project.isEmpty {
                Label(thread.project, systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePhoneSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct RemotePhoneSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.24 : 0.07), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private extension View {
    func remotePhoneSurface() -> some View { modifier(RemotePhoneSurface()) }
}

private struct RemotePhoneBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if !reduceTransparency {
                LinearGradient(colors: [Color.accentColor.opacity(0.14), .clear, Color.accentColor.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private extension RemoteThreadState {
    var phoneSymbol: String {
        switch self {
        case .running: return "waveform"
        case .ready: return "checkmark.circle"
        case .interrupted: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        case .notLoaded: return "arrow.down.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    var phoneColor: Color {
        switch self {
        case .running: return .accentColor
        case .failed: return .red
        case .interrupted: return .orange
        default: return .secondary
        }
    }
}
