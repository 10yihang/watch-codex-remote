# Watch Codex companion

原生 SwiftUI iPhone + Watch 工程，新增**真实 Remote 实验链路**，演示模式单独保留。

**代码提交 `eac3ae0` 已通过 [云端验证](https://github.com/10yihang/watch-codex-remote/actions/runs/42661689146)：70 个 Swift 测试、iPhone/Watch 无签名模拟器构建和设置页截图。真机登录、注册、配对与控制仍未验证，不能宣称已连通。** 初始真实页面不会显示演示会话。用户逐步确认后，代码会执行浏览器 OAuth、Remote 再授权、Secure Enclave 注册、配对、指定主机、已有会话读取/发送/停止，不需要额外主机桥接或复制电脑令牌。

**MFA/标识符后续修复需单独验证：** 切去 MFA 应用不再主动取消登录页，Bundle ID 改为项目级联动设置。上面的云端结果只对应旧代码 `eac3ae0`，不覆盖这些修复。详情见 [MFA_RECOVERY.md](Docs/MFA_RECOVERY.md)。

打开 `WatchCodex.xcodeproj`。iOS 17+、watchOS 10+，建议 Xcode 16 或更新版本。保留本地开发团队、Bundle Identifier 及 Watch companion ID；不要用模板覆盖已经修好的签名配置。

Bundle Identifier 可在 **PROJECT → WatchCodex → Build Settings → WATCH_CODEX_PHONE_BUNDLE_ID** 中统一调整，Phone / Watch / companion ID 共用该项目设置；具体步骤和已有签名配置迁移见 [BUNDLE_CONFIGURATION.md](Docs/BUNDLE_CONFIGURATION.md)。

旧代码 `eac3ae0` 的云端验证已通过 26 项结构检查、20 项 Node 离线协议测试、70 项 Swift XCTest（零失败），两个模拟器 Target 均构建成功。工具链：Xcode 16.4、Swift 6.1.2；真实账号和硬件行为不在这次验证范围内。

完整实现、限制、来源和逐步真机验收见 [LIVE_CONNECTION.md](Docs/LIVE_CONNECTION.md)。登录、设备注册、配对和真实操作均需明确确认；未知结果不重发。iPhone 必须保持前台解锁，本版本不保证锁屏或后台可用。

运行检查：

```sh
python3 Scripts/check_source.py
node --test ../watch-codex-probe/probe.test.mjs
bash Scripts/verify_apple.sh
```

这是未经服务方验证的第三方私有协议实验，不是官方支持的 Remote 客户端。完整来源许可保留在 `ThirdParty/` 和 probe 的 `upstream/`。
