# Design: sessions at a glance

Mode: Operate. Native SwiftUI for a Chinese-speaking developer checking existing work on an Apple Watch and companion iPhone. This replaces the original diagnostics-first list.

## First viewport
- Watch: small inline Codex title, immediately visible “演示 · Remote 未连接”, then the running example as the primary row. Secondary sessions are shorter, quieter rows. No giant disconnected card or redundant section heading.
- iPhone: native large Codex title, compact demo/disconnected status, then active work with readable title and update. Recent sessions follow as a compact list. Device reachability and receipts sit below the actual work, with full diagnostics in the existing connection screen.
- Every session and action remains explicitly simulated. No fabricated progress percentage, login state, host status, completion, or live remote connection.

## Visual system
- System typography, semantic text styles and Dynamic Type throughout. Headline is the session title on Watch; iPhone uses title2 bold for active work and headline for recent sessions.
- Adaptive cyan-teal accent: light RGB (0, .353, .459), dark (.424, .894, .933), with existing increased-contrast variants. Watch explicitly uses the dark color scheme so its black canvas never gets the inaccessible light-mode accent.
- Watch surfaces: black canvas, active row accent at 12% opacity, secondary rows white at 7%; 18-point continuous corners, 12-point internal padding, 10-point row spacing.
- iPhone surfaces: systemGroupedBackground canvas, secondarySystemGroupedBackground active/connection surfaces, no shadows or decoration. 24-point outer padding and vertical rhythm; active row 22-point padding and 24-point continuous corner, connection row 16-point padding/corner.
- Native NavigationStack, NavigationLink, ScrollView, Button, List detail screens, confirmations and system input. No custom navigation gestures, animation, font dependency or drawing framework.

## Behavior preserved
- Existing snapshots and thread/turn IDs, source selection and WatchConnectivity remain unchanged.
- Disabled send while running, unreachable, pending or unreconciled; retained drafts; exact captured turn for stop confirmation.
- No silent fallback, background-queued mutation, automatic retry, new thread or fork.
- Empty snapshots, receipts and diagnostics remain accessible. Full implementation boundaries stay on the connection screen.

## Verification
The source and offline protocol suites are run before publication. The existing Apple CI builds both simulator apps, runs core tests and captures actual iPhone light/dark/accessibility and large/small Watch screens. Captures must be visually inspected before claiming a passed visual review. Simulator captures are not physical-device or end-to-end connectivity verification.
