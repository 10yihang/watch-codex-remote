# 验证报告

验证日期：2026-11-04（UTC）。平台：Linux；Node.js 24.22.1；Python 3.12.14。

## 已执行并通过

- **16 项 Python 源码/工程检查**：两个现代应用 target、PBX 引用完整性、Swift 文件存在、bundle/companion 对应、嵌入 Watch 关系、scheme XML、无 Remote 认证/网络/凭证代码、命令不进入后台队列、失败刷新保留未知状态、无 thread 创建/fork、明确演示文案、停止确认捕获 turn、后台任务排空条件、浅深/高对比强调色对比度、工程生成确定性、18 项 Swift 测试存在。
- **20 项上一阶段 Node 离线探针测试**：全部通过，测试内容及约束保留在 `watch-codex-probe/README.md`。这些是原探针的测试，不是原生 Swift 测试。
- Python 脚本语法检查通过。
- 对最终源码做独立静态审查，修复回调递归、失败刷新误解锁、摘要长度边界、后台任务过早完成、停止弹窗目标被新快照替换等问题。

原始输出：`source-check-results.txt`、`probe-test-results.txt`。

## 已尝试但被环境阻塞

`bash Scripts/verify_apple.sh` 返回退出码 2：

> BLOCKED: Full Xcode and Swift are required. No Apple build has run.

这不是 Apple 编译失败日志，也不是 Swift 测试失败；工具链不存在，Apple 编译/测试没有运行。

## 已写好但未运行

- **18 项 Swift XCTest**：编码往返、大小边界、演示来源约束、重复快照 ID、缺失 turn、未来快照、命令时间边界、模式/版本、输入边界、额外字段、复用已有 thread、拒绝未知 thread、重复 ID 幂等与内容变更、运行中重复发送、明确 turn 停止、缺失 turn、刷新不改变会话、未知操作解码失败。
- Xcode 工程解析与 iOS/watchOS 模拟器构建。
- SwiftUI 原生界面、浅深色、Dynamic Type、VoiceOver、真实截图。
- iPhone ↔ Apple Watch 物理链路、后台任务时序、锁屏/断连/回执丢失/重启行为。
- 真实 Remote 的授权、配对、协议兼容、现有 thread 读取或执行。

## 验证能说明什么

源码/结构检查可以发现特定结构错误与已知回归，不能替代 Swift 类型检查、Xcode build 或真机测试。独立静态审查同样不能证明可安装或线上可用。

交付状态：**原生工程与演示实现已编写，云内可运行检查通过，Apple 平台构建与真机验证待做，Remote 直连尚未实现。**

下一步按 `DEVICE_CHECKLIST.md` 在得到授权的 Mac/设备上运行。不把任何一层的通过换算成另一层通过。
