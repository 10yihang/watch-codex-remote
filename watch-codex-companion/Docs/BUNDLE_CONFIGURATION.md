# 在 Xcode 界面调整 iPhone / Watch 标识符

这份工程用一个项目级设置关联三个值，不固定任何个人 Bundle Identifier，也不需要反复编辑 Watch 的 Info.plist。

1. 打开 `WatchCodex.xcodeproj`，点左侧蓝色工程图标。
2. 在中间选择 **PROJECT → WatchCodex**（不是 TARGETS 下的 Phone 或 Watch）。
3. 打开 **Build Settings**，选择 **All**，搜索 `WATCH_CODEX_PHONE_BUNDLE_ID`。它位于 **User-Defined**。
4. 把默认的 `org.example.watchcodex` 改成你自己的 iPhone Bundle Identifier。展开该行，确认 **Debug 和 Release** 都使用需要的值。已有本地签名配置时填入原来的 iPhone ID，不要另换一个 ID。
5. 两个 Target 的 **Signing & Capabilities** 中继续选择你自己的开发团队，保留已有签名设置。

工程自动引用这个设置：

- Phone Bundle Identifier：`$(WATCH_CODEX_PHONE_BUNDLE_ID)`
- Watch Bundle Identifier：`$(WATCH_CODEX_PHONE_BUNDLE_ID).watchkitapp`
- Watch 的 `WKCompanionAppBundleIdentifier`：`$(WATCH_CODEX_PHONE_BUNDLE_ID)`

例如把项目设置改成 `com.example.personalremote`，三个解析后的值分别是 `com.example.personalremote`、`com.example.personalremote.watchkitapp`、`com.example.personalremote`。示例不是必须使用的 ID。

## 从已经手工修改过的工程迁移

Xcode **不会**自动跨 Target 读取另一个 Target 在 Signing & Capabilities 中填写的标识符。如果只在 Phone 的 Signing & Capabilities 中覆盖 Bundle Identifier，Watch 不会跟着变。

迁移时先记录原来的 Phone / Watch 标识符及开发团队；将原 Phone ID 填到上述项目设置，然后在两个 Target 的 **Build Settings → Packaging → Product Bundle Identifier** 中恢复上述变量表达式（Debug / Release 都检查）。不要更改开发团队、证书或其他签名设置。如果原来的 Watch ID 使用不同后缀，可以保留自己的 Watch Product Bundle Identifier，但它应满足 Apple 对伴随应用标识符的要求，且 Watch 的 companion ID 仍引用项目设置。

`iPhone/Info.plist` 和 `Watch/Info.plist` 现在都显示在左侧 Project Navigator，方便查看。通常不用修改其中的 companion 字段。

## 生成器与验证边界

`Scripts/generate_project.py` 用于生成仓库模板，会覆盖生成的工程、两个 plist 和 scheme，并将模板设置还原为 `org.example.watchcodex`。**完成本地签名配置后不要直接运行生成器或用模板覆盖工程**；如确需重新生成，先备份本地配置，再在 Xcode 恢复 ID 和团队。此更改不读取或修改本机签名证书。

离线检查：`python3 Scripts/check_bundle_configuration.py`。它验证项目结构、两个构建配置和多个合成 ID 的变量替换，不等于 Xcode 或真机验证。

有 Xcode 的 Mac 上还需检查两个 Target 的 Build Settings 解析值，并进行无签名模拟器构建，检查构建产物 Info.plist 中的 `CFBundleIdentifier` 和 `WKCompanionAppBundleIdentifier`。真机安装、签名和配对需要另行验收。

### 安全的模板检查与 Mac 验证

`Scripts/check_source.py` 是仓库**源码模板**的检查入口，已经包含 bundle 配置检查。它的生成器检查只在独立临时目录生成并重复比较，不会重写当前工程或本地签名配置。个人修改过的工程可能因与默认模板不同而检查失败，这是模板差异，不代表个人签名无效；检查失败也不会恢复或覆盖你的配置。

`Scripts/verify_apple.sh` 在 Mac 上将 `WATCH_CODEX_PHONE_BUNDLE_ID=net.example.watchcodex.validation` 作为命令行参数传给无签名构建，不修改工程文件或开发团队。脚本将验证：

- Debug 的 Phone 和 Watch 实际构建产物中，标识符均已展开为非默认值；Watch companion 与 Phone 一致。
- Phone 产物中实际嵌入的 Watch 也有一致的标识符。
- Release 的 `xcodebuild -showBuildSettings -json` 同样正确解析非默认设置。这里不执行 Release 构建。

验证产物保存在 `.build/apple`。截图脚本 `capture_simulators.py` 从产物 Info.plist 读取启动 ID，并先检查 companion 关系，不再假设默认 ID。模拟器截图脚本会安装和启动应用，仅在明确需要该验证时运行。

Linux 上能检查 shell/Python 语法、合成 plist 和构建设置样本；不能据此声称 Xcode 已构建或验证了真实产物。
