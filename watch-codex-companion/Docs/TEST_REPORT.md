# 验证报告

## 2026-11-09 cloud validation update

Native connection and dormant OAuth code at `fa96253133a17fc27d32cb9949c2d64e6fdd8646` passed [run 42632249643](https://github.com/10yihang/watch-codex-remote/actions/runs/42632249643): 24 project/source checks, 20 Node protocol tests, 49 Swift core tests, both unsigned simulator builds and demo screenshot capture. Xcode 16.4 / Swift 6.1.2 were used. OAuth is still disabled; no real login, Keychain operation, device enrolment, pairing, live host command or physical-device test was performed. The core tests do not exercise the OAuth runtime. A follow-up resolves a Notification sendability warning; check the exact current commit's CI as well.

The original preparation report below is historical. Its earlier “not run” Apple-build statements were superseded by the cloud evidence above, not by the local source checks.


> 以下为历史演示版本的结果，不验证本次新原生 Remote 代码。本次状态见 [REMOTE_IMPLEMENTATION.md](REMOTE_IMPLEMENTATION.md)：源码检查和 Node 测试通过，Swift/Xcode 与真实连接仍未运行。

验证日期：2026-11-05（UTC）。最终功能修复源码：`9a30cee10bb193bc01055efec0b38fd32ff60cfa`。

[GitHub Actions 成功记录](https://github.com/10yihang/watch-codex-remote/actions/runs/41960076332) · [完整 Apple 构建日志](https://github.com/10yihang/watch-codex-remote/actions/runs/41960076332/artifacts/13385012340)（artifact 保留至 2026-11-12）。

## 已执行并通过

- **16 项 Python 源码/工程检查**：工程引用、双 target 与嵌入关系、scheme、演示边界、命令状态约束、工程生成确定性等。
- **20 项 Node 离线协议测试**：协议编码、签名与边界测试；不是线上 Remote 联调。
- **18 项 Swift XCTest**：在 GitHub 标准 `macos-15` 云端 runner 上执行，0 failures。
- **Xcode 工程加载**：`xcodebuild -list` 识别两个 target 与两个 shared scheme。
- **iPhone 模拟器构建**：`WatchCodexPhone`，Debug，`generic/platform=iOS Simulator`，成功；包含嵌入 Watch App。
- **Watch 模拟器构建**：`WatchCodexWatch`，Debug，`generic/platform=watchOS Simulator`，成功。

Apple 工具链为 Xcode 16.4（16F6）、Swift 6.1.2。两个构建均设置 `CODE_SIGNING_ALLOWED=NO`；没有访问用户的 Mac，没有设备安装、登录、配对或签名。

## 首次云端构建发现并修复

[首次运行](https://github.com/10yihang/watch-codex-remote/actions/runs/41959627037)的 18 项 Swift 核心测试通过，但 iPhone 的 `PhoneThreadView` 报 SwiftUI 类型检查超时。将带 footer 的输入区 Section 改为明确的 header/content/footer 初始化形式后，重新运行全部检查，两个模拟器构建通过。没有更改发送、停止、来源或权限行为。

## 尚未执行

- 原生界面实际运行、浅深色、Dynamic Type、VoiceOver、交互验收与真实截图。
- iPhone ↔ Apple Watch 真机链路、后台任务时序、锁屏、断连、回执丢失、重启行为。
- 安装包签名、真机安装与分发。
- 真实 Codex Remote 授权、配对、协议兼容、现有 thread 读取或执行。

## 结论与边界

**演示工程已通过云端 Swift 测试和 iPhone/watchOS 模拟器编译。仍不是可连接真实 Remote 的 MVP。** 编译通过不代表 UI 已验收、真机可用或 Remote 已连通。

2026-11-04 的 Linux 检查曾因缺少 Apple 工具链而无法执行编译；上面的云端运行补齐的是构建证据，不是其余平台验收。后续步骤见 `DEVICE_CHECKLIST.md`。每次源码变更后，以对应提交的 Actions 结果为准。
