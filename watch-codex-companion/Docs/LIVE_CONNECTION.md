# Experimental real connection candidate

Prepared from public main `f7de9114fbfa6f64c768464988d507de8bb40e93`. Local work only: no publication, CI dispatch, login, credential creation, enrollment or production Remote request occurred during implementation.

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

App backgrounding/cancellation serializes teardown before allowing another operation. No automatic reconnect, background relay, notification wake or queued Watch mutations. The current UX requires an unlocked foreground iPhone.

## Compatibility assumptions and limits

This is an unofficial integration, not OpenAI approval. The pinned NightBlood source reports a working iPhone route, but that report is not validation of this app, its signing team or current service behavior. Public client ID availability is not a guarantee of accepted scope/redirect/enrollment/relay access. Token payload checks are routing/consistency checks, not cryptographic JWT verification; the HTTPS service remains authoritative.

- Full Xcode, Apple SDK compilation and physical hardware behavior are unverified for this revision.
- Secure Enclave enrollment requires a physical compatible iPhone. There is no software-key simulator fallback.
- Maximum 20 recent threads. No pagination UI yet. Explicitly refresh for progress; app-server push notifications are not projected into UI.
- The phone/Watch projection clips displayed text to keep messages bounded. It does not change thread/turn IDs or execution state.
- Relay frame cap is 150 KiB; chunked responses are rejected. Large thread histories can fail rather than being partially decoded. There is no claim that all existing sessions fit.
- Approval requests from the host are not handled here. Respond to them on the trusted host; no automatic approval or permission downgrade is attempted.
- The app does not change development team, certificates, device trust or Developer Mode.

## Verification completed here

- 26 Python source/project guardrails passed, including deterministic project generation, isolated live/demo protocols and device-key call-site checks.
- 12 nested native OAuth source guardrails passed.
- 20 existing Node offline protocol tests passed.
- Added unit tests for native claims, real thread parsing/RPC shapes, live wire boundaries, enrollment aliases and finish-response shape. Total: 70 Swift test methods, **not run for this revision**.
- Static code review found and fixed account commit order, refresh recovery, failed-connect socket cleanup, stale review evidence and asynchronous teardown races.
- `verify_apple.sh` was invoked and exited with the explicit Full Xcode/Swift blocker. No Apple build or Swift test started. Historical passing CI is not reused as evidence for this candidate.

## Next acceptance gates

1. Owner-approved publication/build or build this local candidate on a Mac. Run all 70 Swift tests and both unsigned simulator targets on the exact final source. Fix compilation/test failures before any real login.
2. Retain existing local bundle/signing settings. Verify phone bundle ID matches Watch's `WKCompanionAppBundleIdentifier`, both targets use the same development team, and installation succeeds. Do not regenerate over custom signing settings blindly.
3. On an unlocked physical iPhone, confirm the experimental sign-in prompt. Verify cancel/back/background return cleanly, account continuity, Keychain restore and explicit refresh. Do not copy tokens or send credentials/screenshots containing them.
4. Explicitly enroll this phone. Verify system user-presence prompting, the exact returned account/client, revocation and interrupted/unknown recovery without replay.
5. Enable Remote in the existing Codex desktop app as needed, generate a pairing code, confirm the intended host, then compare a real thread ID and content against the host. Only that proves actual connection.
6. Choose a disposable existing test thread and harmless command. Confirm one send, then separately confirm an exact-current-turn stop. Check repeat taps, stale turns, disconnect, expiry, background, restart and a lost reply without duplicate execution.
7. Validate Watch pairing/reachability, same-account/host binding, phone foreground requirement, unknown-result lock, accessibility and display on real devices.

## Reference evidence

- [NightBlood native route and restrictions](https://github.com/jonathanroomer/NightBloodRemote/tree/4824aceb1cd04ac521f7f0342771c20edad60dac).
- [OpenAI app-server Thread schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts), with ThreadStatus, Turn, TurnStatus and request schemas inspected during this work. Main-branch schema is compatibility evidence, not a promise about a particular desktop version.
- Original rcodex signing and relay source is pinned in the probe's upstream README and licenses.
