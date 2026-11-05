# Design: frosted sessions

Mode: Operate. Native SwiftUI for a Chinese-speaking developer checking existing work on an Apple Watch and companion iPhone. This design adds a frosted-glass feel to the session-first layout. The user’s “iOS 27” reference describes a visual direction, not an SDK or platform capability claim.

## First viewport
- Watch: small inline Codex title, immediately visible “演示 · Remote 未连接”, then the running example as the primary row. Secondary sessions are shorter, quieter rows. No giant disconnected card or redundant section heading.
- iPhone: native large Codex title, compact demo/disconnected status, then active work with readable title and update. Recent sessions follow as a compact list. Device reachability and receipts sit below the actual work, with full diagnostics in the existing connection screen.
- Every session and action remains explicitly simulated. No fabricated progress percentage, login state, host status, completion, or live remote connection.

## Visual system
- System typography, semantic text styles and Dynamic Type throughout. Headline is the session title on Watch; iPhone uses title2 bold for active work and headline for recent sessions.
- Adaptive cyan-teal accent: light RGB (0, .353, .459), dark (.424, .894, .933), with existing increased-contrast variants. iPhone retains the adaptive asset. Watch uses the explicit `watchAccent` constant (RGB .424, .894, .933), including `.tint(watchAccent).accentColor(watchAccent)` at the app root and direct status/surface references. The dark color scheme remains forced, but that environment setting alone did not correct actual Watch asset resolution.
- Watch surfaces: native ultraThinMaterial for every session row, 18-point continuous corners, 12-point internal padding, 10-point row spacing, and a 0.5-point white border at 14% opacity. Running emphasis comes from the cyan status and headline title, not a different row fill. A restrained top-leading to bottom-trailing gradient runs from black through watchAccent at 16% opacity to black.
- iPhone surfaces: ultraThinMaterial active card and thinMaterial Apple Watch connection card. White 0.5-point edge highlights use 30% and 22% opacity respectively. Keep 24-point outer padding and vertical rhythm, active-card 22-point padding/24-point continuous corner, and connection-card 16-point padding/corner. No custom shadows.
- iPhone backdrop: systemGroupedBackground with blurred accent/cyan and blue ellipses. Accent ellipse: opacity .22, width 1.2×/height .6× canvas, blur 55 points, offset (−.35× width, −.25× height). Blue ellipse: opacity .12, width 1×/height .5×, blur 65 points, offset (.35× width, .2× height). Backdrop ignores safe areas and is accessibility-hidden.
- iPhone secondary copy uses Color.primary.opacity(0.65) for root disclosure, session metadata/summary, connection metadata and receipts; tertiary chevrons and semantic detail-state/count styles remain unchanged.
- The active-card status/project header switches through AnyLayout to a leading vertical stack with 8-point spacing at accessibility Dynamic Type sizes; otherwise it is horizontal with an 8-point minimum spacer.
- Native NavigationStack, NavigationLink, ScrollView, Button, List detail screens, confirmations and system input. No custom navigation gestures, animation, font dependency or drawing framework.

## Behavior preserved
- Existing snapshots and thread/turn IDs, source selection and WatchConnectivity remain unchanged.
- Disabled send while running, unreachable, pending or unreconciled; retained drafts; exact captured turn for stop confirmation.
- No silent fallback, background-queued mutation, automatic retry, new thread or fork.
- Empty snapshots, receipts and diagnostics remain accessible. Full implementation boundaries stay on the connection screen.

## Compatibility and verification
This source implementation requires simulator verification before visual sign-off. No final contrast, accessibility or visual QA pass is claimed. The implementation uses native SwiftUI materials supported by the existing Xcode 16.4 toolchain and project deployment targets (materials available on iOS 15+ and watchOS 10+). It deliberately does not use glassEffect, which requires SDK 26.

Before visual sign-off, build both simulator apps, run the source/protocol suites, and visually inspect iPhone light/dark/accessibility and large/small Watch captures. Inspect text contrast over translucent materials and system accessibility settings. Simulator captures do not establish physical-device or end-to-end connectivity verification.
