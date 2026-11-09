---
name: Watch Codex companion
description: Native frosted sessions for live iPhone and Apple Watch surfaces
---

# Design System: Native frosted sessions

## Overview

The live iPhone and Apple Watch interfaces use native frosted surfaces, subtle tinted backdrops and semantic system typography. Setup is guided by actual connection state; once connected, existing sessions precede collapsed connection settings. Watch remains compact and task-focused. The user's “iOS 27” reference is visual direction, not an SDK capability claim: deployment remains iOS 17+ / watchOS 10+ with Xcode 16.4, without `glassEffect`.

**Scope:** `iPhone/LiveRemoteView.swift` and `Watch/LiveWatchView.swift` are the redesigned real-session surfaces. `iPhone/PhoneRootView.swift` and `Watch/WatchRootView.swift` remain separate, unchanged demo surfaces. Demo data and actions stay explicitly simulated; that restriction does not relabel real sessions as demos.

Native SwiftUI colors, materials, semantic typography and point-based dimensions are normative in `.impeccable/design.json` under `extensions.native.liveSurfaces` and `demoSurfaces`. They are not converted into CSS aliases or fixed font metrics. Frontmatter intentionally contains metadata only because native material and adaptive color values do not fit portable CSS token primitives.

**Validation:** source-only documentation review. Xcode and Swift are unavailable here, so no new build, simulator/device render, visual, contrast or interaction verification is claimed. No push or cloud build was performed. Build and test both targets, then inspect light/dark iPhone, small/large Watch, accessibility text sizes, Reduce Transparency, increased contrast, real connection states and confirmation/recovery flows before sign-off. Simulator checks alone do not establish physical-device connectivity.

## Colors

### Live surfaces
- iPhone retains the adaptive `AccentColor` asset: sRGB light (0, 0.353, 0.459), dark (0.424, 0.894, 0.933), increased-contrast light (0, 0.255, 0.337), increased-contrast dark (0.6, 0.961, 0.984), all alpha 1.
- Watch uses explicit `watchAccent`, sRGB (0.424, 0.894, 0.933), with the existing app-root tint/accent and dark scheme. Do not assume the adaptive asset supplies Watch colors.
- Text uses semantic primary and secondary styles. Running state uses the platform accent; failed uses red, interrupted orange, other session states secondary. Symbols and readable labels accompany state colors. Uncertain results use orange warning copy.
- Phone backdrop: systemGroupedBackground plus a top-leading to bottom-trailing accent gradient at 0.14, clear, 0.05. Watch backdrop: black plus watchAccent at 0.13 fading to clear. Both omit the gradient with Reduce Transparency and hide decorative backgrounds from accessibility.

### Unchanged demo surfaces
The same accent palette remains. Demo iPhone secondary copy uses primary at 0.65 opacity; its backdrop retains blurred accent and blue ellipses, not the new live gradient. Demo Watch retains black → watchAccent at 0.16 → black. Full retained native values live under `demoSurfaces`, not as defaults for live screens.

## Typography

Use system semantic styles and Dynamic Type, without custom font families, fixed line heights or a fabricated scale ratio.

### Live surfaces
- iPhone overview: title2 bold; section headings: title3 semibold; session title: headline; session state: subheadline semibold; connection steps: subheadline medium; summary/status: subheadline.
- Phone identifiers: caption monospaced. Session counts use subheadline monospaced digits, composer counts caption monospaced digits.
- Watch titles: headline; row state: caption2 medium; detail state: caption semibold; detail summary: body; supporting copy: caption/caption2; composer counts: caption2 monospaced digits.

### Unchanged demo surfaces
Watch active title remains headline and recent titles subheadline medium. Demo iPhone active title remains title2 bold and recent titles headline. These differ from the live row hierarchy; do not copy them indiscriminately.

## Layout

### Live iPhone
Content-sized vertical scrolling uses 20-point horizontal inset, 8-point root top inset, 32-point bottom inset and 28-point section gap. Detail uses 12-point top inset. Surface content padding is 20. The overview groups heading, three steps, read status, busy cancellation and experimental disclosure. Its 48-point circular symbol uses accent at 0.09 opacity. Steps use 12-point spacing, switching from horizontal to leading vertical layout at accessibility Dynamic Type sizes.

Sessions use a 14-point row gap. Each row has 12-point content spacing, full-height title, summary capped at three lines and project capped at two. A recovery panel may precede sessions. While disconnected, account/controller setup is visible and host setup appears after enrollment. While connected, sessions precede a collapsed connection-settings disclosure. A connected empty session collection remains an honest empty state.

### Live Watch
Use 10-point horizontal and 16-point bottom insets, 16-point section spacing, 14-point surface padding and 8-point row spacing within a row. Keep host/reachability and snapshot time compact; show uncertainty before sessions when present. Preserve snapshot order. Titles are capped at three lines; project at one. The detail summary wraps. Utility copy uses a 4-point horizontal inset. No fixed breakpoints.

### Unchanged demo surfaces
Watch retains 10-point horizontal inset, 8-point bottom inset, 10-point row gaps and 12-point row padding. Phone retains 24-point horizontal inset/section rhythm, 22-point active-card padding and 16-point connection-card padding. Its active header stacks with 8-point spacing at accessibility sizes. Demo first viewport remains explicit demo/disconnected disclosure followed by simulated work; it is not the live onboarding layout.

## Elevation & Depth

### Live surfaces
Phone uses `regularMaterial`; Watch uses `ultraThinMaterial`. Reduce Transparency replaces these with secondarySystemGroupedBackground on phone and `Color(white: 0.12)` on Watch. Phone has a 0.5-point primary outline at 0.07 opacity, increasing to 0.24 for increased contrast. Watch uses a 0.5-point white outline at 0.14, increasing to 0.4. Outlines do not receive hit testing. There are no custom shadows, blurred ellipses or custom visual animations in these live views.

### Unchanged demo surfaces
Phone active cards retain ultraThinMaterial, 0.5-point white edge at 0.30; connection cards retain thinMaterial, edge at 0.22. Accent ellipse opacity is 0.22 with 55-point blur; blue ellipse opacity is 0.12 with 65-point blur. Demo Watch rows retain ultraThinMaterial and a white 0.5-point edge at 0.14. No custom shadows. Do not treat retained demo depth as the live material specification.

## Shapes

Live surfaces use continuous rounded rectangles: 24-point phone corners and 20-point Watch corners. The phone overview icon uses a circle. Demo Watch retains 18-point corners; demo phone active and connection cards retain 24 and 16 respectively. Native buttons and fields keep platform-defined shapes rather than invented radius tokens.

## Components

### Live connection overview and setup
Account, controller and host step completion comes directly from `signedIn`, `enrolled` and `snapshot.connected`. There is no invented percentage or staged success. Busy state shows the actual status and cancellation; idle status remains selectable on phone. Experimental/unverified wording stays visible. Pairing uses a native rounded-border SecureField; offline host controls are disabled. Host rows have 16-point vertical padding and dividers.

### Live session rows and detail
Plain NavigationLinks expose status symbols, titles and supporting context with combined accessibility children. Details group session context separately from latest read status and composition. Watch rows omit the phone summary for density. The session list is real data only, without demo fallback.

### Live buttons and input
Native bordered and borderedProminent buttons retain system behavior. Phone uses large control size; selected labels have a 24-point minimum height, which is not a measured total hit-target claim. Watch action labels use a 44-point minimum height. Phone host refresh has a 44-by-44 minimum frame. Phone composition is multiline, three through eight lines; Watch uses the native TextField. Both show a 2000-character count and preserve draft/confirmation behavior. Mutation gates remain controlled by busy, reachability, freshness, review and input validity conditions as applicable to each platform. Refresh enablement is intentionally strengthened: phone session refresh is disabled while busy or disconnected, the empty-state refresh button appears only when connected, and Watch refresh also requires a connected snapshot. Stop remains destructive and requires a current turn. Native alerts show host, environment, session and the proposed send/stop target before execution.

Session refresh controls read “刷新会话” and invoke `controller.refresh()`; host-list refresh reads “刷新主机列表” and invokes `loadHosts()`. These are distinct actions. Host selection still requires its existing confirmation.

### Live recovery and navigation
Uncertain-operation warnings, explicit read/review actions and locks remain visible. The design does not establish that a remote mutation succeeded. Phone uses the Codex Remote root title and inline real-session detail title; Watch uses Remote and real-session detail navigation. All three phone disclosure labels (connection settings, connection information and session identifiers) have a 44-point minimum height and rectangular content shape. Device reachability is not Remote authorization.

### Unchanged demo components
Demo rows, active/recent hierarchy, Watch connection card, native demo detail fields and simulated confirmations remain documented separately in the sidecar. Existing simulated snapshots, IDs, source selection, WatchConnectivity, retained drafts and operation guards are outside this visual redesign. Do not mix demo receipts with real-operation status.

## Do's and Don'ts

- **Do** select tokens from the correct live or demo scope and retain native system controls.
- **Do** express state with text and symbols, using only actual model evidence.
- **Do** preserve setup, read status, uncertainty, review and experimental disclosures.
- **Do** inspect rendered material contrast, wrapping, hit targets and accessibility settings before approval.
- **Don't** introduce `glassEffect`, an SDK upgrade, fixed font metrics or CSS approximations to describe this implementation.
- **Don't** imply the source review proves build success, visual quality, accessibility compliance or real-device readiness.
- **Don't** fabricate progress, authenticated state, online hosts, successful operations or live session data.
- **Don't** apply the old demo-only “every action is simulated” rule to the real-session surfaces.
