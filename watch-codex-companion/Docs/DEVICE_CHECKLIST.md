# Apple 验收清单（尚未执行）

必须在最终源码上执行，不能用这里的勾选项推断已经通过。

## 1. 编译

- 在 Mac 上运行 `bash Scripts/verify_apple.sh`，保留完整日志。
- `swift test` 的 18 项核心测试通过。
- 两个 shared scheme 分别通过模拟器构建；iPhone 构建含嵌入式 Watch App。
- 若有 SDK/API/actor 错误，修复后重跑上述全部命令。本云交付没有这些编译证据。

## 2. 原生界面

- iPhone 紧凑屏与大屏，竖屏/横屏；watchOS 小/大两类表盘。
- Light/Dark、高对比、大号 Dynamic Type、VoiceOver。
- 标题、中文长指令、长 turn 标识不挤掉操作；系统安全区完整。
- NavigationStack 返回、确认停止后取消、输入后返回再进入、反复点按钮。
- 长任务状态不显示虚假的百分比；无障碍能读出示例来源与当前状态。
- 用 Xcode / `xcrun simctl io <UDID> screenshot <path>` 留存真正原生截图。网页图不算。

## 3. 本机演示

- 第一个示例默认运行：模拟停止 → 输入 → 模拟发送，thread ID 不变，turn ID 更新。
- 第二个示例直接发送；重复发送在 running 时禁用。
- 空输入、空格输入、2000 字、2001 字；Unicode/emoji。
- Remote 始终显示未连接，没有登录、实际授权或真实执行的成功提示。

## 4. 配对设备链路（需要用户自有 iPhone/Apple Watch、Xcode 签名）

只在用户选择真机安装、签名和已有设备配对测试后执行。此包没有为用户操作这些步骤。

- 在 Xcode 两个 target 选择同一开发团队和唯一 bundle ID，同时更新 Watch Info.plist 的 companion ID。
- 安装两个 app 并打开；手表“来源与回执”打开“经 iPhone 演示”，主动刷新。
- 核对手机与手表的 thread ID/turn ID、摘要、快照时间相同。
- 经 Watch 发一个明确标注的演示请求；手机收到后返回与原 request ID 关联的回执。
- 退出前台、锁屏、短时断连、飞行模式、iPhone App 退出再打开。不可达时不偷偷改为本机执行。
- 模拟回执丢失/超过 12 秒：显示未知、不自动重发，发送禁用；刷新失败后仍禁用，刷新成功后才可继续。
- 等待时来源 Toggle 禁用；已显示未知后切换本机/手机，不能绕过手机端的核对要求。
- 快照乱序应忽略旧内容；超过 30 秒的命令被拒绝，指向旧 turn 的停止被拒绝。
- 观察后台 WC 任务：激活且 `hasContentPending == false` 后才完成，不提前结束数据处理。
- 重启 App 后演示状态会重置：本版没有持久状态、持久 dedupe 或真实控制器会话。

## 5. 真实 Remote 接入仍被阻塞

1. 确认服务端支持且获准的 iOS client/redirect/step-up 流程。
2. 明确指定已有 host，取得创建持久密钥、控制器 enroll/pair 的授权。
3. 只读验证 list/read 实际已有 thread，确认目标主机版本。
4. 指定一个已有 thread 与测试指令，再实现/验证 resume/start/interrupt 和事件状态机。
5. 正式实现结果查询、持久幂等/对账、断流恢复与后台生命周期后，才可扩展真实执行。

不得用桌面 OAuth client、搬运桌面 token、创建新 thread、宿主新装 bridge 或模拟成功绕开这些门槛。
