# Watch Codex companion

**代码 `5530409` 已通过[云端验证](https://github.com/10yihang/watch-codex-remote/actions/runs/42674539496)，并查看了五张实际未连接设置页截图。** 这不证明真机 MFA/Face ID、主机会话读取或已连接页面已正常。

截图检查发现深色主按钮文字和 Watch 导航颜色需要提高对比度，后续颜色修正需自己的构建和截图。功能诊断及剩余验收见 [HOST_READ_DIAGNOSTICS.md](Docs/HOST_READ_DIAGNOSTICS.md)，界面范围见 [UI_REDESIGN.md](Docs/UI_REDESIGN.md)。

打开 `WatchCodex.xcodeproj`。iOS 17+、watchOS 10+，建议 Xcode 16 或更新版本。保留本地开发团队、Bundle Identifier 及 Watch companion ID；不要用模板覆盖已经修好的签名配置。

Bundle Identifier 可在 **PROJECT → WatchCodex → Build Settings → WATCH_CODEX_PHONE_BUNDLE_ID** 中统一调整，Phone / Watch / companion ID 共用该项目设置；具体步骤和已有签名配置迁移见 [BUNDLE_CONFIGURATION.md](Docs/BUNDLE_CONFIGURATION.md)。

`5530409` 已通过 28 项结构检查（含 OAuth、Bundle 和 UI 检查）、20 项 Node 测试、80 项 Swift 测试，以及两个无签名模拟器构建。工具链为 Xcode 16.4、Swift 6.1.2。

完整实现、限制、来源和逐步真机验收见 [LIVE_CONNECTION.md](Docs/LIVE_CONNECTION.md)。登录、设备注册、配对和真实操作均需明确确认；未知结果不重发。iPhone 必须保持前台解锁，本版本不保证锁屏或后台可用。

运行检查：

```sh
python3 Scripts/check_source.py
node --test ../watch-codex-probe/probe.test.mjs
bash Scripts/verify_apple.sh
```

这是未经服务方验证的第三方私有协议实验，不是官方支持的 Remote 客户端。完整来源许可保留在 `ThirdParty/` 和 probe 的 `upstream/`。
