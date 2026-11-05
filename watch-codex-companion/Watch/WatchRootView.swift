import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("演示 · Remote 未连接")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    if store.snapshot.threads.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有手机快照").font(.headline)
                            Text("打开 iPhone App 后刷新，或切换到本机演示。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(12)
                    }
                    ForEach(store.snapshot.threads) { thread in
                        NavigationLink { WatchThreadView(threadID: thread.id) } label: {
                            WatchSessionRow(thread: thread)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        Button { store.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel(store.busy ? "等待 iPhone" : "刷新演示")
                        .disabled(store.busy)
                        NavigationLink { WatchConnectionView() } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityLabel("来源与回执")
                    }
                    .buttonStyle(.bordered)
                    Text("\(store.sourceLabel) · \(store.snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .navigationTitle("Codex")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WatchSessionRow: View {
    let thread: ThreadSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if thread.state == .running {
                Label(thread.state.label, systemImage: thread.state.symbol)
                    .font(.caption2.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(thread.title)
                    .font(thread.state == .running ? .headline : .subheadline.weight(.medium))
                    .foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 5) {
                if thread.state != .running {
                    Image(systemName: thread.state.symbol).accessibilityHidden(true)
                }
                Text(thread.project).lineLimit(1)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(thread.state == .running ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(thread.state.label)
    }
}

struct WatchThreadView: View {
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
                        Label(thread.state.label, systemImage: thread.state.symbol).font(.caption)
                            .foregroundStyle(thread.state == .running ? Color.accentColor : .secondary)
                        Text(thread.summary).font(.body)
                    } footer: { Text("演示数据 · Remote 未连接") }
                    Section {
                        TextField("输入演示指令", text: $draft)
                            .accessibilityHint("使用系统键盘或听写，最多 2000 字")
                        Button("模拟发送", systemImage: "arrow.up.circle") {
                            store.send(text: draft, threadID: threadID)
                        }.disabled(!store.canMutate || thread.state == .running || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                        if draft.count > 2000 { Text("请缩短至 2000 字以内").font(.caption).foregroundStyle(.red) }
                        if thread.state == .running {
                            Button("模拟停止", role: .destructive) { stopTarget = thread; confirmStop = true }
                                .disabled(!store.canMutate)
                        }
                    }
                    Section("最近回执") { Text(store.receipt).font(.caption) }
                }
                .navigationTitle(thread.title)
                .confirmationDialog("停止此示例 turn？", isPresented: $confirmStop, titleVisibility: .visible) {
                    Button("模拟停止", role: .destructive) {
                        if let target = stopTarget { store.stop(target) }
                        stopTarget = nil
                    }
                    Button("取消", role: .cancel) { stopTarget = nil }
                }
            } else {
                Text("会话不在快照中。返回刷新，不会新建会话。").padding()
            }
        }
    }
}

struct WatchConnectionView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        List {
            Section("演示来源") {
                Toggle("经 iPhone 演示", isOn: $store.usePhone).disabled(store.busy)
                Text(store.usePhone ? "只发给 iPhone。不可达时不会改成本机执行。" : "所有操作仅在手表本机模拟。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("设备链路") { Text(store.linkStatus).font(.caption) }
            Section("Codex Remote") {
                Label("尚未连接", systemImage: "network.slash")
                Text("原生授权入口待确认。设备链路不代表 Remote 登录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("最近回执") { Text(store.receipt).font(.caption) }
        }.navigationTitle("来源与回执")
    }
}

#Preview { WatchRootView().environmentObject(CompanionStore()) }
