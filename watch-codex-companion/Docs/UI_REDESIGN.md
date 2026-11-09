# Native Remote UI redesign

## Scope

This patch updates the real iPhone and Apple Watch connection and thread screens. The UI patch itself leaves demo screens, controller, account flow, relay, stores, project files and signing settings unchanged. The final combined candidate also includes the separately documented [host-read diagnostics and foreground recovery](HOST_READ_DIAGNOSTICS.md).

The visual direction is frosted native glass with calm teal accents. “iOS 27” is an aesthetic reference, not a minimum OS or SDK claim. Implementation remains compatible in intent with iOS 17, watchOS 10 and Xcode 16.4. It uses native SwiftUI materials, not `glassEffect`.

## What changed

- iPhone groups the actual account, controller and host state in one readable connection surface. Status and cancellation remain visible.
- Connected sessions come before connection settings. Setup moves into a native disclosure instead of permanently occupying the screen.
- Thread screens separate the work summary, current receipt, instruction field, send action and destructive stop action.
- Watch replaces one oversized list cell per status line with a compact host/status group, readable session surfaces and native controls.
- Materials have opaque Reduce Transparency fallbacks. System typography adapts to Dynamic Type; account status stacks vertically at accessibility sizes. Disclosure labels have a 44-point minimum height. No decorative animation is added.

## Behavior preserved and corrected

All login, restore, enrollment, pairing, host selection, revocation, send and stop confirmations remain intact. The captured host binding, thread, turn and message are unchanged. Unknown outcomes still require review. There are no added network calls on launch, layout, navigation or appearance, and no automated replay.

One existing misleading control is corrected: `controller.refresh()` reads an already connected session source; it does not find hosts or create the first connection. Its label is now **刷新会话**, and it is unavailable until `snapshot.connected`. **刷新主机列表** still calls `loadHosts()`, and choosing an online host still requires the original confirmation. Watch refresh also requires a connected snapshot as well as a reachable iPhone.

## Verification status

Local source checks passed:

- `Scripts/check_source.py`: 28 checks in the combined candidate (including nested UI checks).
- `Scripts/check_native_auth.py`: 12 checks.
- `Scripts/check_bundle_configuration.py`: 5 checks.
- `Scripts/check_live_ui.py`: 11 UI source invariants.
- `node --test ../watch-codex-probe/probe.test.mjs`: 20 offline protocol tests.

These checks do not compile Swift or render UI. The local Apple verification command stops before building because Xcode and Swift are unavailable. The combined patch is now approved for publication and a cloud build. Its new simulator evidence must come from that exact commit; no physical-device tests, login, pairing or remote command have been performed. Previously captured screens are the old interface and do not validate this redesign.

## Published build and screenshot review

Code `5530409` passed [cloud run 42674539496](https://github.com/10yihang/watch-codex-remote/actions/runs/42674539496): 80 Swift tests, both unsigned simulator builds and processed bundle-ID checks. Actual iPhone light/dark/accessibility-large and 49 mm/42 mm Watch setup PNGs were inspected. They show only unconnected setup, not connected threads or device authentication. Review found low contrast on dark iPhone prominent labels and the Watch navigation title; the follow-up changes only these colors and requires its own refreshed screenshots.

## Next Apple verification

On an authorized Mac or build runner with Xcode selected:

```sh
python3 Scripts/check_source.py
python3 Scripts/check_native_auth.py
python3 Scripts/check_bundle_configuration.py
python3 Scripts/check_live_ui.py
node --test ../watch-codex-probe/probe.test.mjs
bash Scripts/verify_apple.sh
python3 Scripts/capture_simulators.py
```

The existing capture script launches only the unconnected app. Review its iPhone light/dark/large-text and both Watch-size PNGs. It performs no login or Remote request.

Before visual sign-off, also inspect these states using authorized test data or a test account:

1. Signed out, signed in but not enrolled, enrolled with no hosts, offline host, and connected empty/nonempty sessions.
2. Busy/cancel, recoverable error, unknown operation result and review unlock.
3. Long Chinese titles, host IDs, project paths and messages at large Dynamic Type, with VoiceOver and Reduce Transparency/Increase Contrast.
4. Thread detail, input and system keyboard/dictation; empty/2000/2001-character input; canceled send/stop confirmation; back navigation preserving expected draft behavior.
5. Unreachable iPhone, stale snapshot and connected source transitions. Confirm disabled actions stay disabled and sessions never become demo data.

Real connection success remains a separate functional acceptance question.
