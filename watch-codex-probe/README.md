# Watch Codex Remote：第一阶段离线探针

**这是可运行的协议编码验证，不是可连接主机的 Apple Watch App，也不是已完成的 MVP。**

本阶段验证：设备签名与 App Server 请求结构能否按公开源码重建。
没有登录、读取用户凭证、访问用户 Mac、创建持久密钥、注册控制器、配对主机、打开真实 WebSocket 或发送任何真实指令。

## 运行

需要 Node.js 22+，无第三方依赖、无安装步骤。

```sh
node --test probe.test.mjs
node demo.mjs
```

已在 Linux / Node.js 24.22.1 验证，20 项测试通过。完整输出见 `test-results.txt`。
`offline-demo.json` 是本地生成的假会话帧，明确标记 `OFFLINE_ONLY`、`authenticated: false`、`liveHostTested: false`。
签名私钥只存在内存中，没有私钥输出文件。测试密钥标记为 `offline_test_only`，不能据此宣称具备不可导出硬件保护。

## 已实现与已验证

- `probe.mjs`：纯离线函数，唯一运行时依赖是 Node 内置 `crypto`。没有 HTTP、WebSocket、文件读写、凭证加载或设备注册代码。
- P-256 公钥 X9.63 → SPKI DER 编码，与 Node/OpenSSL 输出逐字节一致。
- ECDSA SHA-256 的 DER 签名及本地验签，篡改数据或签名会失败。
- Enrollment/refresh 与 WebSocket 签名原文，和固定版本 rcodex 测试黄金样例逐字节匹配。签名 JSON 字段顺序不可任意更改。
- 账号、client、目标地址、用途、作用域、nonce、会话 token 摘要、身份 hash、过期时间的拒绝测试。
- Relay v3 `client_message` 外层的 client/env/stream/seq 字段及内部 App Server 请求编码。
- `initialize` → `initialized`、`thread/list`、`thread/read`、`thread/resume`、`turn/start`、`turn/interrupt` 的最小请求形状。
- 只允许读取或恢复已有 thread；没有 `thread/start` 或 `thread/fork`，不会替用户另建会话。
- Resume/turn 不传权限、sandbox、模型或工作目录覆盖项，避免意外改变已有 thread 配置。

`verifySignature` 只验证密码学签名。它不是服务端认证、设备授权或 challenge 防重放验证器。
测试不是“用本地假服务冒充连接成功”：演示没有模拟成功的服务器响应。

## 真实连接还缺什么

1. **合法的原生账号认证入口。** rcodex 从桌面 Codex 的 `auth.json` 获取 ChatGPT session，并用 desktop OAuth client、PKCE 与 localhost 回调完成 step-up。这个仓库没有 iOS 原生 OAuth 实现。不能把桌面 token 搬到手机，不能假定 desktop client 接受 iOS 回调。
2. **新控制器授权。** 已有主机 online 不表示一个新的 iPhone/Watch controller 已有访问权。源码流程会创建独立 controller，再配对已有主机。真正创建持久密钥、enroll 和 pair 前需用户明确确认。
3. **iOS 密钥的服务端接受性。** P-256 算法一致只证明可编码/签名；不证明 relay 接受 iOS 的 key identity/protection class。rcodex 原实现只有 macOS login Keychain。
4. **真实主机版本及 thread 范围。** 本包对照的是固定 rcodex 协议与另一固定版本 OpenAI App Server schema，不是某个真实主机版本的兼容证明。要验证指定主机能列出、读取和恢复用户实际已有 thread，并确认多控制器同时连接时的行为。
5. **完整网络状态机与 Apple 构建。** 没有握手连接、收包、request ID 响应匹配、事件流、旧 stream/重复序列过滤、分块重组、断线恢复、后台生命周期或 SwiftUI 界面。当前环境无 Swift/Xcode，尚未进行 Apple 平台编译、模拟器或真机测试。

读取已有 thread 和恢复运行也不是同一件事。OpenAI 的 `ThreadResumeParams` 注释明确说明：threadId 指向运行中的 thread 时，会 rejoin 该 thread。这里仅验证该请求形状；没有验证某台主机上真实正在运行的 turn。

## 不新增主机 bridge 的最短设计（尚未实现）

```text
Apple Watch UI
      │ 短请求与状态快照
      ▼
iPhone 原生控制器 ── WSS / OpenAI relay ── 已有 Codex Remote 主机
```

- iPhone 承担正式授权、设备签名、relay 连接和最小请求编码；主机不另装常驻 bridge。
- 只有在服务端支持的 client/redirect 流程确认后，才接入原生授权界面。`ASWebAuthenticationSession` 是 UI 机制，不自动赋予未注册的客户端访问权。
- 可评估 Apple Secure Enclave / Keychain 的 P-256 实现；必须保持私钥不可导出，不自动降低保护级别。本文没有创建任何持久密钥。
- JSON 编码必须复用本包黄金向量验证字段顺序、UTF-8、SPKI、DER 与 Base64 细节。
- Watch 的“已送达 iPhone”“Remote 已接受”“完成”应分开显示。后台不可用时显示带时间戳缓存和重试，不把排队成功说成主机执行成功。
- `turn/start` 超时后先查询实际结果，不自动重复提交。`turn/interrupt` 必须携带明确 threadId/turnId，不能变成延迟执行的泛化“停止”。

## 下一阶段的最小验收门槛

按顺序，一步不能替代下一步：

1. 确认有可用且获准的 iOS 账号/step-up 登录方式与回调。若服务端不支持则停止这条原生直连路线，不能绕过认证。
2. 经用户确认，创建设备密钥并 enroll/pair 到明确指定的已有主机；确认可撤销。
3. 只读验证 `initialize → thread/list → thread/read`，对照用户实际 thread。
4. 用户选择指定 thread 和测试指令后，验证 resume、一次 turn/start、状态读取与明确 turn 的 interrupt。不得自动新建 thread 作为失败时替代。
5. 才进入 Swift/watchOS 工程、Xcode 编译和配对真机测试，覆盖锁屏、挂起、断连、重新打开、提交后失联与重复点按。

## 有意缩小的范围

- 出站 JSON 超过 100 KiB 直接拒绝，和 rcodex 开始分块的位置一致；没有分块或大历史读取能力。
- 时间解析接受通常 RFC3339 时间和小数秒，按 upstream 的整数秒时间戳校验；不支持闰秒时间戳。
- 这里只产出帧，不负责按响应推进 initialize/resume 的真实状态机。演示帧列表不是可以不等待响应就发送的脚本。
- `thread/read` 用 metadata-only；`thread/resume` 排除历史。完整历史需要按目标版本补齐 `thread/turns/list` 与 `thread/items/list`。
- 没有日志记录真实 token、持久化密钥、自动配对、登录模拟、host fallback 或自建 proxy。

## 源码依据

检索日期：2026-11-04。所有引用的源文件均保留在 `upstream/`，只作为离线阅读及黄金向量依据，未执行上游程序。

- [rcodex 固定基线 8d839ae](https://github.com/Typiqally/rcodex/tree/8d839ae673e0c8d895e334adbf786ead0325c24d)，MIT，见 `upstream/LICENSE`。rcodex 是非官方实验项目，不是 OpenAI 发布的 SDK。
- [签名 payload 定义](https://github.com/Typiqally/rcodex/blob/8d839ae673e0c8d895e334adbf786ead0325c24d/src/protocol.rs)
- [Session 与 token 绑定校验](https://github.com/Typiqally/rcodex/blob/8d839ae673e0c8d895e334adbf786ead0325c24d/src/relay.rs)
- [WebSocket 握手及外层协议](https://github.com/Typiqally/rcodex/blob/8d839ae673e0c8d895e334adbf786ead0325c24d/src/transport.rs)
- [上游黄金样例](https://github.com/Typiqally/rcodex/blob/8d839ae673e0c8d895e334adbf786ead0325c24d/tests/protocol_contract.rs)
- [OpenAI App Server 类型基线 ede5893](https://github.com/openai/codex/tree/ede589336e9ecc64cb05045c2961fb1277858f1d/codex-rs/app-server-protocol/schema/typescript)，Apache 2.0，见 `upstream/openai/LICENSE`。
- [Apple 原生授权 UI](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)、[Secure Enclave 签名 API](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey)、[原生 WebSocket API](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)。这些 API 的存在不构成服务端授权兼容性证明。
