# Experimental real connection candidate

Prepared from public main `f7de9114fbfa6f64c768464988d507de8bb40e93`. With owner approval, code commit `eac3ae078314628154787fc7a8a6dcbb405a02b6` was published and [cloud run 42661689146](https://github.com/10yihang/watch-codex-remote/actions/runs/42661689146) passed on 2026-11-09. No live login, credential creation, enrollment or production Remote request was performed.

**MFA/bundle follow-up requires separate validation:** the MFA app-switch and bundle-configuration changes in this working copy are not covered by that cloud run. See [MFA_RECOVERY.md](MFA_RECOVERY.md).

## What is now wired

The initial iPhone tab and Watch page are the real route, initially empty/disconnected. The old demo remains separate and labeled. The live code is not a simulation:

1. `RemoteConnectionController` owns explicit operations; construction performs no Keychain/network work.
2. iPhone browser OAuth uses PKCE, state, a local-only callback and the public Codex application ID. Successful ordinary tokens are saved device-only. Re-login to an existing controller checks account identity before replacing stored tokens.
3. A separate enrollment confirmation creates one Secure Enclave identity with user presence, runs the fresh `codex.remote_control.enroll` step-up, binds the device challenge, and submits enrollment finish. Enrollment finish validates account/client/scopes, not a controller token that this response does not promise.
4. Pairing sends the entered code once. A fresh client-scoped host list and explicit host selection are required. No implicit first host.
5. A device proof refresh obtains a short-lived controller token in memory. WebSocket challenge/proof and app-server initialization follow. Connected is shown only after a real `thread/list` response is parsed.
6. Existing-thread send performs a detailed read, explicit resume without configuration overrides, then `turn/start`. Stop verifies the exact current turn before `turn/interrupt`. No thread creation or fork fallback exists.
7. Watch uses a separate versioned live envelope with account/controller/environment/connection binding, UUID, 30-second command expiry, 5-second future tolerance, input/size limits, and immediate reply correlation. Tokens and keys never enter Watch payloads.

## Permission and recovery behavior

Login, persistent controller creation, pairing, host selection and real mutations have separate native confirmation prompts. Private tokens travel only to the fixed OpenAI authentication and Remote origins; redirect following is disabled. Stored tokens and journal items use `WhenUnlockedThisDeviceOnly`, not iCloud synchronization.

The journal records enrollment/pairing/revocation unknown states before the corresponding dispatch. A pending command records its original host/thread/request ID before dispatch. Duplicate request IDs are rejected, not replayed. Unknown mutation state survives restart. To clear it, reconnect to the original host, read the affected thread, inspect the result, and explicitly acknowledge it on iPhone. The original command is never resent. Watch keeps its own uncertain lock if a phone reply is lost and asks for review.

A failed or cancelled enrollment does not automatically erase a possibly registered key. Recovery is deliberately explicit: use the existing controller's revoke action with the same account, or inspect/revoke that controller in the service's account controls. Do not repeatedly enroll to guess the result. There is not yet a richer enrollment reconciliation UI.

Explicit cancellation and backgrounding during Remote operations serialize teardown before allowing another operation. The interactive browser sign-in/step-up phase is an exception: temporary MFA app switching retains the same page, PKCE/state and fixed ten-minute login window. It does not keep a relay alive or preserve state across process termination. No automatic reconnect, background relay, notification wake or queued Watch mutations. The current UX requires an unlocked foreground iPhone.

## Compatibility assumptions and limits

This is an unofficial integration, not OpenAI approval. The pinned NightBlood source reports a working iPhone route, but that report is not validation of this app, its signing team or current service behavior. Public client ID availability is not a guarantee of accepted scope/redirect/enrollment/relay access. Token payload checks are routing/consistency checks, not cryptographic JWT verification; the HTTPS service remains authoritative.

- The previous application code `eac3ae0` compiled for both simulator targets with Xcode 16.4. The subsequent MFA/bundle changes have only local offline checks so far. Physical hardware and live service behavior remain unverified.
- Secure Enclave enrollment requires a physical compatible iPhone. There is no software-key simulator fallback.
- Maximum 20 recent threads. No pagination UI yet. Explicitly refresh for progress; app-server push notifications are not projected into UI.
- The phone/Watch projection clips displayed text to keep messages bounded. It does not change thread/turn IDs or execution state.
- Relay frame cap is 150 KiB; chunked responses are rejected. Large thread histories can fail rather than being partially decoded. There is no claim that all existing sessions fit.
- Approval requests from the host are not handled here. Respond to them on the trusted host; no automatic approval or permission downgrade is attempted.
- The app does not change development team, certificates, device trust or Developer Mode.

## Previous published verification (`eac3ae0`)

- 26 Python source/project guardrails passed, including deterministic project generation, isolated live/demo protocols and device-key call-site checks.
- 12 nested native OAuth source guardrails passed.
- 20 existing Node offline protocol tests passed.
- Added unit tests for native claims, real thread parsing/RPC shapes, live wire boundaries, enrollment aliases and finish-response shape. All 70 Swift tests passed in cloud validation with zero failures.
- Static code review found and fixed account commit order, refresh recovery, failed-connect socket cleanup, stale review evidence and asynchronous teardown races.
- Initial local `verify_apple.sh` correctly stopped because Linux lacked Xcode/Swift. The later [cloud run](https://github.com/10yihang/watch-codex-remote/actions/runs/42661689146) ran that script successfully: 70 Swift tests and both unsigned simulator builds. Five setup screenshots were captured; iPhone and small Watch pixels were inspected. This was not interactive authentication or physical-device QA. The only compiler-adjacent warning was skipped AppIntents metadata because the project has no AppIntents dependency.

## Next acceptance gates

1. **Completed:** owner-approved publication and cloud build for `eac3ae0`. All 70 Swift tests and both unsigned simulator targets passed. Later MFA/bundle fixes need a new approved Apple build.
2. Retain existing local bundle/signing settings. Verify phone bundle ID matches Watch's `WKCompanionAppBundleIdentifier`, both targets use the same development team, and installation succeeds. Do not regenerate over custom signing settings blindly.
3. On an unlocked physical iPhone, confirm the experimental sign-in prompt. Verify MFA app switch/return preserves the login page separately from explicit Cancel/back dismissal. Check timeout, cancellation followed by immediate re-login, process termination, account continuity, Keychain restore and explicit refresh. Do not copy tokens or send credentials/screenshots containing them.
4. Explicitly enroll this phone. Verify system user-presence prompting, the exact returned account/client, revocation and interrupted/unknown recovery without replay.
5. Enable Remote in the existing Codex desktop app as needed, generate a pairing code, confirm the intended host, then compare a real thread ID and content against the host. Only that proves actual connection.
6. Choose a disposable existing test thread and harmless command. Confirm one send, then separately confirm an exact-current-turn stop. Check repeat taps, stale turns, disconnect, expiry, background, restart and a lost reply without duplicate execution.
7. Validate Watch pairing/reachability, same-account/host binding, phone foreground requirement, unknown-result lock, accessibility and display on real devices.

## Reference evidence

- [NightBlood native route and restrictions](https://github.com/jonathanroomer/NightBloodRemote/tree/4824aceb1cd04ac521f7f0342771c20edad60dac).
- [OpenAI app-server Thread schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts), with ThreadStatus, Turn, TurnStatus and request schemas inspected during this work. Main-branch schema is compatibility evidence, not a promise about a particular desktop version.
- Original rcodex signing and relay source is pinned in the probe's upstream README and licenses.
