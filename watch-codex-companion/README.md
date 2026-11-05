# Watch Codex companion

**真实 SwiftUI iPhone + watchOS 工程，当前只有明确标注的演示能力。不是已连通 Codex Remote 的 MVP。**

本包延续上一阶段离线协议探针，新增原生双 Target 工程、交互界面、WatchConnectivity 演示传输以及可在 Swift 工具链运行的核心测试。真实 Remote 授权入口尚未确认，默认始终显示“Remote 未连接”。

## 打开

在装有完整 Xcode 的 Mac 打开 `WatchCodex.xcodeproj`：

- `WatchCodexPhone`：iOS 17+ 的 iPhone companion，嵌入 Watch App。
- `WatchCodexWatch`：watchOS 10+ 的现代单 Target Watch App，无旧式 extension target。
- `Package.swift`：独立纯 Foundation 核心与 18 项 XCTest，可运行 `swift test`。

推荐使用安装了 iOS/watchOS Simulator SDK 的 Xcode 16 或更新版本。已于 2026-11-05 在 GitHub 云端 Xcode 16.4 / Swift 6.1.2 通过 18 项核心测试、工程加载及 iPhone/watchOS 模拟器构建：[构建记录](https://github.com/10yihang/watch-codex-remote/actions/runs/41960076332)。**尚未运行模拟器 UI 或真机测试，也没有接入真实 Remote。**

一次运行所有 Apple 构建前检查：

```sh
bash Scripts/verify_apple.sh
```

脚本只运行核心测试和无签名模拟器构建，不登录、不安装到设备、不配对、不更改账号。真机测试需要你选择开发团队与唯一 bundle ID，并同步修改 Watch Info.plist 中的 `WKCompanionAppBundleIdentifier`。工程没有预设团队、证书或凭证。

## 可体验的功能

- 三个固定 ID 的已有示例会话，浏览状态、项目、摘要和快照时间。
- 在示例会话内输入文本，模拟新 turn；运行中禁用再次发送。
- 停止携带当前 thread ID + turn ID，过期 turn 不会停止替代任务。
- 手表默认“本机演示”，不需要手机可达；可显式切换“经 iPhone 演示”。后一种不可达时不会静默本机执行。
- iPhone 通过 `updateApplicationContext` 发布最新演示快照；Watch 通过可达的 `sendMessage` 发请求，回执按 request ID 核对。
- 消息版本、demo 来源、大小、输入长度、命令有效期、已知 thread、当前 turn 校验；重复 request ID 使用缓存回执，内容变更则拒绝。
- 单个在途请求、12 秒未知结果超时、无自动重发；变更结果未知后要求成功刷新，失败刷新不解除限制。
- 界面区分“设备链路可达”和“Remote 未连接”，不把收到 iPhone 回执描述为真实主机执行完成。

## 明确没有做的事

没有真实 Remote HTTP/WebSocket、账号登录、桌面 token/`auth.json` 导入、desktop client 冒用、设备持久密钥、enroll/pair、Mac 访问或真实指令发送。没有建立新 thread/fork，也没有覆盖 thread 的权限、sandbox、模型或工作目录。

`Shared/Core.swift` 定义的是本工程自己的 **Watch ↔ iPhone 演示协议**，不冒充 Codex Remote relay 协议。原探针仍在相邻 `watch-codex-probe` 目录；本交付 ZIP 同时包含其原始副本供对照。该探针的签名 golden tests 通过，不代表 Swift 已实现签名或 iOS 已获授权。

## 文件

- `Shared/Core.swift`：纯模型、编码边界、已有示例 thread 状态机。
- `Shared/Connectivity.swift`：真实 WatchConnectivity API，最新快照与即时请求/回执。
- `Shared/CompanionStore.swift`：界面状态、明确来源、未知结果和手动刷新。
- `iPhone/`、`Watch/`：SwiftUI App 与界面，现代 watchOS 生命周期处理。
- `Tests/CompanionCoreTests/`：18 项 Swift XCTest，已在 GitHub 云端运行并全部通过。
- `Scripts/check_source.py`：可在 Linux 执行的结构检查，不是 Swift 编译器。
- `Scripts/generate_project.py`：无外部依赖的确定性工程生成器；日常直接打开已生成工程即可。修改过 bundle ID/签名后不要直接重跑生成器，否则会回到模板默认值。
- `Docs/TEST_REPORT.md`、`Docs/DEVICE_CHECKLIST.md`：已做检查与待做验收分开记录。

## 已知限制

- 全部会话为示例。输入可能经系统听写识别，但不会发送到 Codex Remote。
- 演示状态与去重缓存仅在内存；App 重启会恢复示例。不能用于真实幂等保障。
- `updateApplicationContext` 是最新状态、尽力送达；不承诺持续后台连接或即时唤醒。真实设备可达性必须按实测处理。
- Watch ↔ iPhone 的时钟允许最多 5 秒未来偏差，命令 30 秒失效，快照允许 30 秒未来偏差。时间错位可能导致明确拒绝，不能据此宣称恶意请求已被完整防御。
- 60 KiB 消息上限是本工程自己的保守边界，不是 Apple 限额保证。没有文件分块或完整历史同步。
- 仅中文 UI；无 App Store 图标、分发配置、通知、复杂功能、后台 Remote socket 或生产监控。
- 已针对浅色/深色配置高对比强调色，使用原生列表与语义字体。原生视觉、Dynamic Type、VoiceOver 尚未实测，不提供伪造的原生截图。

## 官方依据与协议基线

- [Apple：现代单 Target Watch App](https://developer.apple.com/documentation/watchos-apps/migrating-to-a-single-target-watchos-app)
- [Apple：WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Apple：WatchConnectivity 数据传输](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [Apple：watchOS 后台任务](https://developer.apple.com/documentation/watchkit/using-background-tasks)
- 先前离线探针固定基线及 MIT/Apache-2.0 上游版权文件见其 `README.md` 与 `upstream/`，原样保留。

这些 API 文档说明平台能力，不证明服务端接受原生 iOS Remote 客户端。真实授权、密钥、指定主机和已有 thread 联调是下一道独立门槛。
