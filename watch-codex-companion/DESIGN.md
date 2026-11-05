# Design: a compact native work list

Mode: Operate. Dense enough to scan at a glance, with native navigation and readable Chinese text. Device conventions take precedence over decoration.

- NavigationStack + List; system back behavior, scrolling, confirmations, keyboard and watch dictation remain intact.
- Primary content is the existing thread title; project and explicit demo state are subordinate. Short summaries appear on iPhone, full summaries in detail. No progress percentage is fabricated.
- One adaptive blue-cyan accent: light RGB (0, .353, .459), dark (.424, .894, .933), plus increased-contrast variants. Semantic foreground/background colors elsewhere.
- Large native title on iPhone overview, inline title in detail. All body and control text uses semantic SwiftUI styles. No hard-coded type sizes, web fonts, decorative glass, gradients or custom animation.
- System List/Toggle/TextField/Button/confirmationDialog interactions. Destructive controls are named “模拟停止” and bind the exact displayed turn.
- State vocabulary: “Remote 未连接”, “本机演示”, “iPhone 演示”, “等待 iPhone”, “结果未知”. Never show a generic connected badge for both links.
- Disabled send while running, unreachable, pending or unreconciled; retain the draft. Timestamp every snapshot; explain empty, unreachable, rejected and unknown states.

Visual verification status: source review and accent contrast calculation only. No Xcode, simulator, screenshot, Dynamic Type or physical-device rendering was available in the cloud. Do not describe this file as a passed visual review.
