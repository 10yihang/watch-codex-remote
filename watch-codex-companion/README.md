# Watch Codex companion

**真实 SwiftUI iPhone + watchOS 工程，当前只有明确标注的演示能力。不是已连通 Codex Remote 的 MVP。**

本工程已继续加入原生设备签名、Secure Enclave 密钥提供器、注册/配对 HTTP 与已有会话只读 relay。独立 iOS Remote 授权入口仍未确认，因此这些连接组件保持未启用，界面始终显示“Remote 未连接”。详见 [连接实现与验收门槛](Docs/REMOTE_IMPLEMENTATION.md)。

## 打开

在装有完整 Xcode 的 Mac 打开 `WatchCodex.xcodeproj`：

- `WatchCodexPhone`：iOS 17+ 的 iPhone companion，嵌入 Watch App。
- `WatchCodexWatch`：watchOS 10+ 的现代单 Target Watch App，无旧式 extension target。
- `Package.swift`：演示核心及原生 Remote 协议测试，可在 Apple Swift 工具链运行 `swift test`。

推荐使用安装了 iOS/watchOS Simulator SDK 的 Xcode 16 或更新版本。旧演示版曾通过云端 Swift/Xcode 检查：[历史记录](https://github.com/10yihang/watch-codex-remote/actions/runs/41960076332)。**原生连接与登录准备代码 `fa96253` 已通过 [2026-11-09 云端检查](https://github.com/10yihang/watch-codex-remote/actions/runs/42632249643)：49 个 Swift 核心测试、iPhone/Watch 无签名模拟器构建及演示截图步骤。** 登录、Keychain、Secure Enclave 和真实 Remote 尚未验证；这些核心测试不覆盖 OAuth 运行流程。后续改动应以对应提交的检查结果为准。

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

尚未实现获准的 iOS 账号登录流程、真实会话 UI/Watch 接入或真实指令发送。HTTP/WebSocket、设备密钥和 enroll/pair 已写入原生代码，但从未用于真实账号或主机。没有桌面 token 导入、desktop client 冒用、自动密钥创建、自动注册、Mac 访问、新 thread/fork 或权限覆盖。

`Shared/Core.swift` 仍然只定义 **Watch ↔ iPhone 演示协议**，不混用真实 relay。`RemoteSigning.swift` 与 `RemoteRelay.swift` 独立实现原生协议层；Swift 编译和离线测试通过不代表 iOS 已获 Remote 授权。

## 文件

- `Shared/Core.swift`：纯模型、编码边界、已有示例 thread 状态机。
- `Shared/Connectivity.swift`：真实 WatchConnectivity API，最新快照与即时请求/回执。
- `Shared/CompanionStore.swift`：界面状态、明确来源、未知结果和手动刷新。
- `iPhone/`、`Watch/`：SwiftUI App 与界面，现代 watchOS 生命周期处理。
- `Shared/RemoteAPI.swift`、`RemoteRelay.swift`、`RemoteSigning.swift`：原生 HTTP、只读 WebSocket 和签名组件。
- `iPhone/RemoteDeviceKey.swift`：需明确调用的 Secure Enclave/Keychain 设备密钥提供器。
- `Tests/CompanionCoreTests/`：原有演示测试及新增原生协议测试；基线 `fa96253` 的 49 个 Swift 核心测试已在云端通过，OAuth 运行流程未测试。
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
