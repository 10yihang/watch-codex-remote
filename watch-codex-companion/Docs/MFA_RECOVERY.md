# MFA 切换与 Bundle Identifier 本地修复

基线：公开 main `e286197883f4dbf5efd4127f57dd7422911bbcf9`。本轮获准推送至原仓库 main 并运行云端构建。最新结果应以本次提交对应的 Actions 为准，批准启动不等于已经成功。旧代码 `eac3ae0` 的成功构建不能证明本次修改已编译或通过真机验收。

## 登录页为什么消失

原实现有两条主动取消路径：`PhoneApp` 收到后台场景事件会调用 `disconnect()`，`CodexPlanOAuth` 又会监听进入后台并取消 OAuth。两者都可能关闭 Safari 登录页。因此切到 MFA 应用会被我们自己的代码当成取消，不能把这个现象直接归因于 iOS 的必然限制。

修复后：

- 只有正在浏览器中登录或进行 Remote 再授权时，临时切到 MFA 应用才保留当前操作、Safari 页面和原来的 PKCE/state。
- 登录窗口最长十分钟，切换应用不会重置计时。收到回调后等待应用回到前台再继续；等待期间仍检查取消和到期。
- 点 Safari 的取消/关闭，或在应用中明确取消，仍会终止当前操作并清理监听器。不会自动重新登录。
- 实际 Remote 连接、发送、停止、注册完成和配对操作仍受前台限制；后台不保留 relay，不排队真实命令，也不自动重放。
- 认证状态不跨应用进程终止保存。没有添加后台运行权限或保活技巧。

iOS 仍可能挂起进程、使 loopback 监听器失效，或在内存压力下终止应用。此时需要重新登录。保留页面的源代码修改不等于已证明所有 iPhone 上都能可靠完成 MFA。当前仍使用已有 `SFSafariViewController` 与 HTTP localhost 回调约定，没有擅自换成尚未注册的回调地址。

## 标识符现在怎么改

在 Xcode 的 **PROJECT → WatchCodex → Build Settings → All → User-Defined → WATCH_CODEX_PHONE_BUNDLE_ID** 中填入原来的 iPhone Bundle Identifier，检查 Debug 和 Release。两个 Target 的开发团队继续用原来的值。

Phone 标识符、默认 Watch 标识符以及 Watch companion 字段都引用这一设置。只覆盖 Phone Target 的 Signing & Capabilities 标识符不会自动传播到其他 Target；已有本地覆盖时，按 [BUNDLE_CONFIGURATION.md](BUNDLE_CONFIGURATION.md) 恢复变量引用。不要为了更新换一个新 ID，也不要用模板重写已配置好的签名项目。

Bundle Identifier 是构建与签名设置，不是安装后在 App 内更改的账号设置。这次提供的是 Xcode 界面配置，不能在已安装的 App 内更换其签名身份。

## 验证范围

本地已通过 26 项结构检查（其中嵌套执行 12 项 OAuth 和 5 项 Bundle 检查）、20 项 Node 离线协议测试，以及 Python 语法与 shell 语法检查。检查日志保存在本目录的 `mfa-*.txt`。新增 Swift 单元测试覆盖固定窗口、不续期、过期边界及非法期限；当前环境没有 Swift/Xcode，新增 Swift 测试未执行，实际构建产物 plist 也尚未验证。

新的 Apple 验证脚本将使用非默认 Bundle ID 构建模拟器应用，并检查产物标识符与 companion 关联。只有该脚本在 Mac 或经批准的云端运行成功后，才能声称构建验证通过。

真机验收请分开记录以下情况：

1. 打开登录页，切去 MFA 应用约三十秒，返回是否仍停留原页面，随后完成登录。
2. 连续多次切换，不应新开登录页、不应更新原期限。
3. 点 Safari 取消/关闭，返回 App 后重新登录，旧操作不应关闭新页面。
4. 超过十分钟、强制终止 App、监听器失败：显示明确失败，需要用户重新发起，不自动恢复或重试。
5. 已经建立真实 Remote 连接时切后台：连接应关闭，Watch 命令不能在后台继续或排队，回到前台也不自动重连。
6. 用自定义 ID 验证两个 Target 签名、安装、Watch 配对，检查处理后的三个标识符一致。真实登录和设备注册继续按各自的授权步骤操作。

取消不会删除已经成功保存的登录凭据。如果取消发生在令牌保存完成的瞬间，后续显式恢复可能发现已有登录；这不表示之前的浏览器操作仍在后台运行。

Apple 参考：[后台执行限制](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)、[SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller)、[ASWebAuthenticationSession 回调类型](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback)。
