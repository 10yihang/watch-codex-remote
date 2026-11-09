import SwiftUI

struct LiveWatchView: View {
    @ObservedObject var store: LiveCompanionStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.snapshot.connected ? store.snapshot.hostName : "尚未连接")
                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                        Label(store.reachable ? "iPhone 可达" : "iPhone 不可达",
                              systemImage: store.reachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                            .font(.caption2).foregroundStyle(.secondary)
                        if store.snapshot.connected {
                            Text("快照 \(store.snapshot.generatedAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 4)

                    if store.uncertain {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("待核对", systemImage: "exclamationmark.triangle")
                                .font(.headline).foregroundStyle(Color.orange)
                            Text("上次操作结果未确认。先在 iPhone 核对并解除锁定，再读取此会话详情并核对。")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                        }.remoteWatchSurface()
                    }

                    if store.snapshot.threads.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "text.bubble").font(.title2).foregroundStyle(watchAccent)
                                .accessibilityHidden(true)
                            Text("先在 iPhone 连接").font(.headline)
                            Text("登录、配对并选择主机后，已有会话会出现在这里。无演示数据。")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.remoteWatchSurface()
                    }
                    ForEach(store.snapshot.threads) { thread in
                        NavigationLink {
                            LiveWatchThreadView(store: store, threadID: thread.id)
                        } label: {
                            RemoteWatchThreadRow(thread: thread)
                        }.buttonStyle(.plain)
                    }

                    Button { store.refresh() } label: {
                        Label("刷新会话", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.busy || !store.reachable || !store.snapshot.connected)
                    if store.busy { ProgressView("正在读取…").font(.caption) }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.receipt).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("实验性 · 未完成实机验证")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                }
                .padding(.horizontal, 10).padding(.bottom, 16)
            }
            .background { RemoteWatchBackdrop() }
            .navigationTitle("Remote")
        }
        .tint(watchAccent).accentColor(watchAccent)
        .preferredColorScheme(.dark)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if let thread {
                        Label(thread.state.label, systemImage: thread.state.watchSymbol)
                            .font(.caption.weight(.semibold)).foregroundStyle(thread.state.watchColor)
                    }
                    Text(thread?.title ?? threadID).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(thread?.summary ?? "读取详情后操作")
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                }.remoteWatchSurface()

                Button { store.read(threadID) } label: {
                    Label("读取最新详情", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).disabled(store.busy || !store.reachable)
                Text(store.receipt).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                if store.uncertain && store.canReview {
                    Button("已核对结果，解除锁定") { store.reviewed() }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("继续会话").font(.headline)
                    TextField("发送内容", text: $text)
                        .accessibilityHint("最多 2000 字，检查后还需要确认才能发送")
                    Text("\(text.count) / 2000").font(.caption2.monospacedDigit())
                        .foregroundStyle(text.count > 2000 ? Color.red : Color.secondary)
                }.padding(.horizontal, 4)
                Button { prepare(.sendText) } label: {
                    Label("检查并发送", systemImage: "arrow.up")
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(watchAccent)
                .disabled(!store.canMutate || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                Button(role: .destructive) { prepare(.interrupt) } label: {
                    Label("停止当前轮次", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canMutate || thread?.currentTurnID == nil)
                Text("主机：\(store.snapshot.hostName)\n会话：\(threadID)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
            .padding(.horizontal, 10).padding(.bottom, 16)
        }
        .background { RemoteWatchBackdrop() }
        .navigationTitle("真实会话")
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

private struct RemoteWatchThreadRow: View {
    let thread: RemoteThread
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(thread.state.label, systemImage: thread.state.watchSymbol)
                    .font(.caption2.weight(.medium)).foregroundStyle(thread.state.watchColor)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            Text(thread.title).font(.headline).foregroundStyle(.primary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if !thread.project.isEmpty {
                Text(thread.project).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .remoteWatchSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct RemoteWatchSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.12))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private extension View {
    func remoteWatchSurface() -> some View { modifier(RemoteWatchSurface()) }
}

private struct RemoteWatchBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color.black
            if !reduceTransparency {
                LinearGradient(colors: [watchAccent.opacity(0.13), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private extension RemoteThreadState {
    var watchSymbol: String {
        switch self {
        case .running: return "waveform"
        case .ready: return "checkmark.circle"
        case .interrupted: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        case .notLoaded: return "arrow.down.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    var watchColor: Color {
        switch self {
        case .running: return watchAccent
        case .failed: return .red
        case .interrupted: return .orange
        default: return .secondary
        }
    }
}
